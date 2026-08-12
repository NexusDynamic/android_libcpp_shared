import 'dart:io';

import 'package:android_libcpp_shared/src/locate_ndk.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

/// The environment variable that overrides where `libc++_shared.so` comes from.
///
/// It may point either directly at a `libc++_shared.so`, or at the root of an
/// NDK installation to use in preference to any that would be discovered.
///
/// Note that Gradle reuses a long lived daemon, so a variable that was exported
/// after the daemon started will not reach the build hook. The
/// [libcppSharedPathUserDefine] user define is not affected by that and is the
/// more reliable of the two.
const androidLibcppSharedPathEnvVar = 'ANDROID_LIBCPP_SHARED_PATH';

/// The `pubspec.yaml` user define that overrides where `libc++_shared.so`
/// comes from:
///
/// ```yaml
/// hooks:
///   user_defines:
///     android_libcpp_shared:
///       libcpp_shared_path: /path/to/libc++_shared.so
/// ```
///
/// As with [androidLibcppSharedPathEnvVar], it may point at either the library
/// itself or at the root of an NDK installation.
const libcppSharedPathUserDefine = 'libcpp_shared_path';

/// The outcome of looking for `libc++_shared.so` for a build.
final class LibcppResolution {
  /// The resolved library, or `null` if none could be found.
  final Uri? libcppShared;

  /// The NDK the library was found in, if it came from a located NDK.
  final NDKInfo? ndk;

  /// Every file path that was checked, in the order they were checked.
  final List<Uri> probed;

  /// Human readable notes about the NDKs that were considered and why they
  /// were rejected.
  final List<String> notes;

  LibcppResolution({
    required this.libcppShared,
    required this.ndk,
    required this.probed,
    required this.notes,
  });

  /// A multi line description of everything that was searched, for use in error
  /// messages and bug reports.
  String describeFailure(Architecture targetArchitecture, int minApiLevel) {
    final buffer = StringBuffer()
      ..writeln(
        'Could not find libc++_shared.so for target architecture '
        '$targetArchitecture (minimum NDK API level $minApiLevel).',
      );
    if (notes.isEmpty) {
      buffer.writeln('No Android NDK installation was found.');
    } else {
      buffer.writeln('NDK installations considered:');
      for (final note in notes) {
        buffer.writeln('  - $note');
      }
    }
    if (probed.isNotEmpty) {
      buffer.writeln('Files checked:');
      for (final uri in probed) {
        buffer.writeln('  - ${uri.toFilePath()}');
      }
    }
    buffer
      ..writeln(
        'A file is only accepted if it exists and is an ELF shared object, so '
        'a partially extracted or corrupt NDK is rejected here rather than '
        'producing a broken build.',
      )
      ..writeln(
        'If the library is somewhere else on this machine, point this package '
        'at it and build again, either in the application pubspec.yaml:\n'
        '  hooks:\n'
        '    user_defines:\n'
        '      android_libcpp_shared:\n'
        '        $libcppSharedPathUserDefine: /path/to/libc++_shared.so\n'
        'or by setting $androidLibcppSharedPathEnvVar to the same path. Both '
        'also accept the root of an NDK installation to use.',
      )
      ..write(
        'Please include this message when reporting an issue at '
        'https://github.com/NexusDynamic/android_libcpp_shared/issues',
      );
    return buffer.toString();
  }
}

/// Finds the root of the project being built by walking up from [start] until a
/// directory containing a `.dart_tool` directory is found.
///
/// The build hook runs with its output directory inside the application's
/// `.dart_tool/hooks_runner/`, so this recovers the application directory, and
/// with it the `local.properties` that Flutter and Gradle use.
Uri? findProjectRoot(Uri start, {int maxDepth = 8}) {
  var current = Directory.fromUri(start).absolute.uri;
  for (var depth = 0; depth < maxDepth; depth++) {
    if (Directory.fromUri(current.resolve('.dart_tool/')).existsSync()) {
      return current;
    }
    final parent = current.resolve('../');
    if (parent == current) {
      break;
    }
    current = parent;
  }
  return null;
}

/// Locates `libc++_shared.so` for the target of [input].
///
/// Sources are tried in this order:
///
/// 1. The [androidLibcppSharedPathEnvVar] override.
/// 2. The NDK the Flutter tool reported in the build config, which is the NDK
///    the rest of the build is using.
/// 3. Every other NDK installation that can be found, highest version first.
///
/// A candidate is only accepted once it has been verified to exist and to be an
/// ELF shared object, so the returned [LibcppResolution.libcppShared] is always
/// usable.
/// [environment] defaults to the process environment and exists for testing.
Future<LibcppResolution> resolveLibcppShared(
  BuildInput input, {
  Logger? logger,
  Map<String, String>? environment,
}) async {
  final probed = <Uri>[];
  final notes = <String>[];
  final config = input.config;
  environment ??= Platform.environment;

  // An explicit override, from the pubspec user defines or the environment.
  final userDefine = input.userDefines.path(libcppSharedPathUserDefine);
  final override = userDefine != null
      ? (
          path: Directory.fromUri(userDefine).path,
          source: 'the $libcppSharedPathUserDefine user define',
        )
      : switch (environment[androidLibcppSharedPathEnvVar]?.trim()) {
          final String value when value.isNotEmpty => (
            path: value,
            source: '\$$androidLibcppSharedPathEnvVar',
          ),
          _ => null,
        };
  final overrideNdkPaths = <Uri>[];
  if (override != null) {
    final path = override.path;
    logger?.info('Using ${override.source} to find libc++_shared.so: $path');
    if (Directory(path).existsSync()) {
      overrideNdkPaths.add(Directory(path).uri);
      notes.add('${override.source} = $path (used as an NDK root)');
    } else {
      final uri = File(path).absolute.uri;
      probed.add(uri);
      if (isElfFile(uri)) {
        return LibcppResolution(
          libcppShared: uri,
          ndk: null,
          probed: probed,
          notes: notes..add('${override.source} = $path'),
        );
      }
      notes.add(
        '${override.source} = $path is neither a directory nor an ELF shared '
        'object, ignoring it',
      );
      logger?.warning(notes.last);
    }
  }

  // The compiler the Flutter tool selected identifies the exact NDK, and the
  // exact host toolchain within it, that the rest of the build uses.
  final compiler = config.code.cCompiler?.compiler;
  if (compiler != null) {
    final ndkRoot = NDKLocator.ndkRootFromCompiler(compiler);
    if (ndkRoot != null) {
      logger?.fine(
        'Build config C compiler ${compiler.toFilePath()} belongs to the NDK '
        'at ${ndkRoot.toFilePath()}',
      );
      overrideNdkPaths.add(ndkRoot);
    }
  }

  final projectRoot = findProjectRoot(input.outputDirectory);
  logger?.fine('Project root: ${projectRoot?.toFilePath() ?? 'not found'}');

  final ndks = await NDKLocator.locate(
    logger: logger,
    projectRoot: projectRoot,
    extraNdkPaths: overrideNdkPaths,
  );
  logger?.info('Found ${ndks.length} NDK installation(s).');

  for (final ndk in ndks.allForBuildConfig(config, logger: logger)) {
    final target = ndk.hostArchitectures.first.targetArchitectures.first;
    final resolved = target.resolveLibcppShared(
      ndkRoot: ndk.path,
      probed: probed,
      logger: logger,
    );
    if (resolved != null) {
      return LibcppResolution(
        libcppShared: resolved,
        ndk: ndk,
        probed: probed,
        notes: notes,
      );
    }
    notes.add(
      'NDK ${ndk.version} at ${ndk.path.toFilePath()} has no usable '
      '${target.arch.toTriple()} libc++_shared.so',
    );
    logger?.warning(notes.last);
  }

  if (ndks.isNotEmpty && notes.isEmpty) {
    notes.add(
      '${ndks.length} NDK installation(s) found, but none support '
      '${config.code.targetArchitecture} at API level '
      '${config.code.android.targetNdkApi}',
    );
  }

  return LibcppResolution(
    libcppShared: null,
    ndk: null,
    probed: probed,
    notes: notes,
  );
}
