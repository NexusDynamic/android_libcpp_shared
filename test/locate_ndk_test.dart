import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';
import 'package:android_libcpp_shared/src/locate_ndk.dart';
import 'package:android_libcpp_shared/src/resolve_libcpp.dart';

/// The host toolchain directory name this machine's NDKs would use.
final hostTag = '${HostOS.fromString(Platform.operatingSystem)}-x86_64';

/// A minimal but valid ELF header, enough for [isElfFile].
final elfBytes = <int>[0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00];

/// Creates a fake NDK installation under [parent].
///
/// [libcppTriples] are the triples that get a real (ELF) `libc++_shared.so`;
/// every triple in [triples] is created regardless, so an NDK missing the
/// library for one architecture can be simulated. [linkerScriptTriples] get the
/// `<api>/libc++.so` linker script that the NDK really ships, which must never
/// be mistaken for the shared object.
Uri createFakeNdk(
  Directory parent, {
  required String name,
  required String revision,
  List<String> triples = const [
    'aarch64-linux-android',
    'arm-linux-androideabi',
    'x86_64-linux-android',
  ],
  List<String>? libcppTriples,
  List<String> linkerScriptTriples = const [],
  List<int> apiLevels = const [21, 24, 30],
  String host = '',
  bool legacyCxxStl = false,
}) {
  final hostName = host.isEmpty ? hostTag : host;
  final root = Directory('${parent.path}/$name')..createSync(recursive: true);
  File(
    '${root.path}/source.properties',
  ).writeAsStringSync('Pkg.Desc = Android NDK\nPkg.Revision = $revision\n');
  final sysrootLib =
      '${root.path}/toolchains/llvm/prebuilt/$hostName/sysroot/usr/lib';
  for (final triple in triples) {
    final tripleDir = Directory('$sysrootLib/$triple')
      ..createSync(recursive: true);
    for (final api in apiLevels) {
      final apiDir = Directory('${tripleDir.path}/$api')..createSync();
      if (linkerScriptTriples.contains(triple)) {
        // What the NDK actually ships here: a text linker script.
        File(
          '${apiDir.path}/libc++.so',
        ).writeAsStringSync('INPUT(-lc++_shared -lc++abi)');
      }
    }
    if ((libcppTriples ?? triples).contains(triple)) {
      if (legacyCxxStl) {
        final abi = LibArch.fromTriple(triple)!.toAbi();
        final legacyDir = Directory(
          '${root.path}/sources/cxx-stl/llvm-libc++/libs/$abi',
        )..createSync(recursive: true);
        File('${legacyDir.path}/libc++_shared.so').writeAsBytesSync(elfBytes);
      } else {
        File('${tripleDir.path}/libc++_shared.so').writeAsBytesSync(elfBytes);
      }
    }
  }
  return root.uri;
}

BuildInput fakeBuildInput(
  Directory outputDirectory, {
  Architecture targetArchitecture = Architecture.arm64,
  int targetNdkApi = 21,
  Uri? compiler,
}) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: Directory.current.uri,
      packageName: 'android_libcpp_shared',
      outputDirectoryShared: outputDirectory.uri,
      outputFile: outputDirectory.uri.resolve('output.json'),
    )
    ..setupBuildInput()
    ..config.setupBuild(linkingEnabled: false)
    ..addExtension(
      CodeAssetExtension(
        targetArchitecture: targetArchitecture,
        targetOS: OS.android,
        linkModePreference: LinkModePreference.dynamic,
        android: AndroidCodeConfig(targetNdkApi: targetNdkApi),
        cCompiler: compiler == null
            ? null
            : CCompilerConfig(
                compiler: compiler,
                archiver: compiler.resolve('llvm-ar'),
                linker: compiler.resolve('ld.lld'),
              ),
      ),
    );
  return builder.build();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('libcpp_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('locate returns non-empty set of paths', () async {
    final ndkPaths = await NDKLocator.locate();
    expect(ndkPaths, isNotEmpty);
  });

  group('architecture parsing', () {
    test('maps the build config names, including ia32', () {
      expect(LibArch.fromString('arm64'), LibArch.arm64);
      expect(LibArch.fromString('arm'), LibArch.arm);
      expect(LibArch.fromString('x64'), LibArch.x86_64);
      expect(LibArch.fromString('ia32'), LibArch.x86);
      expect(LibArch.fromString('riscv64'), LibArch.riscv64);
    });

    test('returns null rather than throwing for unknown values', () {
      expect(LibArch.fromString('riscv32'), isNull);
      expect(LibArch.fromTriple('not-a-triple'), isNull);
      expect(HostOS.fromString('fuchsia'), isNull);
      expect(HostArch.fromString('ppc64'), isNull);
    });

    test('maps triples and ABI directory names', () {
      expect(LibArch.arm64.toTriple(), 'aarch64-linux-android');
      expect(LibArch.arm64.toAbi(), 'arm64-v8a');
      expect(LibArch.arm.toAbi(), 'armeabi-v7a');
    });
  });

  group('NDK inspection', () {
    test('parses version, host, triples and API levels', () async {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'fake',
        revision: '28.2.13676358',
      );
      final ndks = await NDKLocator.locate(extraNdkPaths: [ndkPath]);
      final ndk = ndks.firstWhere((n) => n.path == ndkPath);

      expect(ndk.version.toString(), '28.2.13676358');
      final host = ndk.findHost(HostOS.fromString(Platform.operatingSystem)!)!;
      final target = host.findTarget(LibArch.arm64)!;
      expect(target.apiLevels.map((a) => a.level), containsAll([21, 24, 30]));
      expect(target.highestMatching(21)!.level, 30);
      expect(target.highestMatching(99), isNull);
    });

    test('rejects a directory that is not an NDK', () async {
      final notAnNdk = Directory('${tempDir.path}/empty')..createSync();
      final ndks = await NDKLocator.locate(extraNdkPaths: [notAnNdk.uri]);
      expect(ndks.where((n) => n.path == notAnNdk.uri), isEmpty);
    });
  });

  group('libc++_shared.so resolution', () {
    Future<NDKTargetArchitecture> targetOf(Uri ndkPath, LibArch arch) async {
      final ndks = await NDKLocator.locate(extraNdkPaths: [ndkPath]);
      final ndk = ndks.firstWhere((n) => n.path == ndkPath);
      return ndk
          .findHost(HostOS.fromString(Platform.operatingSystem)!)!
          .findTarget(arch)!;
    }

    test('finds the library in the sysroot', () async {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'complete',
        revision: '28.2.13676358',
      );
      final target = await targetOf(ndkPath, LibArch.arm64);
      final probed = <Uri>[];
      final resolved = target.resolveLibcppShared(
        ndkRoot: ndkPath,
        probed: probed,
      );

      expect(resolved, isNotNull);
      expect(resolved!.pathSegments.last, 'libc++_shared.so');
      expect(File.fromUri(resolved).existsSync(), isTrue);
      expect(probed, isNotEmpty);
    });

    test('falls back to the legacy sources/cxx-stl location', () async {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'legacy',
        revision: '21.4.7075529',
        legacyCxxStl: true,
      );
      final target = await targetOf(ndkPath, LibArch.arm64);
      final resolved = target.resolveLibcppShared(ndkRoot: ndkPath);

      expect(resolved, isNotNull);
      expect(
        resolved!.toFilePath(),
        contains('sources/cxx-stl/llvm-libc++/libs/arm64-v8a'),
      );
    });

    test('never accepts the <api>/libc++.so linker script', () async {
      // Regression test for issue #5: the API level directory ships a text
      // linker script named libc++.so, which is not a shared object.
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'no-arm64-lib',
        revision: '28.2.13676358',
        libcppTriples: const ['arm-linux-androideabi'],
        linkerScriptTriples: const ['aarch64-linux-android'],
      );
      final target = await targetOf(ndkPath, LibArch.arm64);
      final probed = <Uri>[];
      final resolved = target.resolveLibcppShared(
        ndkRoot: ndkPath,
        probed: probed,
      );

      expect(resolved, isNull);
      expect(probed, isNotEmpty);
      expect(
        probed.map((u) => u.toFilePath()),
        everyElement(isNot(endsWith('libc++.so'))),
      );
    });

    test('rejects a truncated or non-ELF library', () async {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'corrupt',
        revision: '28.2.13676358',
      );
      final target = await targetOf(ndkPath, LibArch.arm64);
      final libcpp = target.sysrootLibPath.resolve('libc++_shared.so');
      File.fromUri(libcpp).writeAsStringSync('not an elf file');

      expect(isElfFile(libcpp), isFalse);
      expect(target.resolveLibcppShared(ndkRoot: ndkPath), isNull);
    });
  });

  group('discovery helpers', () {
    test('derives the NDK root from the build config compiler', () {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'from-compiler',
        revision: '29.0.14206865',
      );
      final compiler = ndkPath.resolve(
        'toolchains/llvm/prebuilt/$hostTag/bin/clang',
      );

      expect(NDKLocator.ndkRootFromCompiler(compiler), ndkPath);
      expect(
        NDKLocator.ndkRootFromCompiler(Uri.file('/usr/bin/clang')),
        isNull,
      );
    });

    test('reads sdk.dir and ndk.dir from local.properties', () {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'sdk/ndk/29.0.14206865',
        revision: '29.0.14206865',
      );
      final sdkDir = Directory('${tempDir.path}/sdk');
      final projectRoot = Directory('${tempDir.path}/app/android')
        ..createSync(recursive: true);
      File('${projectRoot.path}/local.properties').writeAsStringSync(
        '# comment\n'
        'sdk.dir=${sdkDir.path}\n'
        'ndk.dir=${Directory.fromUri(ndkPath).path}\n',
      );

      final properties = NDKLocator.readLocalProperties(
        Directory('${tempDir.path}/app').uri,
      );
      expect(properties.sdkDir, sdkDir.uri);
      expect(properties.ndkDir, Directory.fromUri(ndkPath).uri);
    });

    test('finds the project root from a hook output directory', () {
      final projectRoot = Directory('${tempDir.path}/app')..createSync();
      final outputDirectory = Directory(
        '${projectRoot.path}/.dart_tool/hooks_runner/pkg/abc',
      )..createSync(recursive: true);

      expect(findProjectRoot(outputDirectory.uri), projectRoot.uri);
      expect(findProjectRoot(Directory.systemTemp.uri, maxDepth: 1), isNull);
    });
  });

  group('resolveLibcppShared', () {
    test(
      'skips an incomplete NDK in favour of an older complete one',
      () async {
        // The higher versioned NDK is missing the arm64 library, as reported in
        // issue #5, so resolution has to continue to the next one.
        final broken = createFakeNdk(
          tempDir,
          name: 'broken',
          revision: '99.0.0',
          libcppTriples: const [],
          linkerScriptTriples: const ['aarch64-linux-android'],
        );
        final good = createFakeNdk(tempDir, name: 'good', revision: '98.0.0');

        final ndks = await NDKLocator.locate(extraNdkPaths: [broken, good]);
        final input = fakeBuildInput(tempDir);
        final matches = ndks.allForBuildConfig(input.config);

        // Highest version first, so the broken one is tried first.
        expect(matches.first.path, broken);
        expect(matches.map((n) => n.path), containsAll([broken, good]));

        final resolved = matches
            .map(
              (ndk) => ndk.hostArchitectures.first.targetArchitectures.first
                  .resolveLibcppShared(ndkRoot: ndk.path),
            )
            .firstWhere((uri) => uri != null);
        expect(
          resolved!.toFilePath(),
          startsWith(Directory.fromUri(good).path),
        );
      },
    );

    test('prefers the NDK named by the environment override', () async {
      final ndkPath = createFakeNdk(
        tempDir,
        name: 'override',
        revision: '30.0.0',
      );

      final resolution = await resolveLibcppShared(
        fakeBuildInput(tempDir),
        environment: {
          androidLibcppSharedPathEnvVar: Directory.fromUri(ndkPath).path,
        },
      );

      expect(resolution.ndk!.path, ndkPath);
      expect(
        resolution.libcppShared!.toFilePath(),
        startsWith(Directory.fromUri(ndkPath).path),
      );
    });

    test('accepts an override pointing straight at a library', () async {
      final libcpp = File('${tempDir.path}/libc++_shared.so')
        ..writeAsBytesSync(elfBytes);

      final resolution = await resolveLibcppShared(
        fakeBuildInput(tempDir),
        environment: {androidLibcppSharedPathEnvVar: libcpp.path},
      );

      expect(resolution.libcppShared, libcpp.absolute.uri);
      expect(resolution.ndk, isNull);
    });

    test('fails with an actionable message when nothing is usable', () async {
      // The NDK has no riscv32 libraries at all, so nothing can match.
      final resolution = await resolveLibcppShared(
        fakeBuildInput(tempDir, targetArchitecture: Architecture.riscv32),
        environment: {},
      );

      expect(resolution.libcppShared, isNull);
      final message = resolution.describeFailure(Architecture.riscv32, 21);
      expect(message, contains('libc++_shared.so'));
      expect(message, contains(androidLibcppSharedPathEnvVar));
      expect(
        message,
        contains('github.com/NexusDynamic/android_libcpp_shared'),
      );
    });
  });
}
