import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:android_libcpp_shared/src/process.dart';
import 'package:glob/list_local_fs.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';

/// Represents a host architecture that can be used for building with the Android NDK.
enum HostArch {
  x64,
  arm64,
  armv7;

  /// Returns the string representation of this HostArch in the format used by the NDK toolchain directories
  @override
  String toString() {
    switch (this) {
      case HostArch.x64:
        return 'x86_64';
      case HostArch.arm64:
        return 'arm64';
      case HostArch.armv7:
        return 'armv7';
    }
  }

  /// Parses a string representation of a host architecture and returns the corresponding HostArch enum value.
  static HostArch? fromString(String str) {
    switch (str) {
      case 'x86_64':
        return HostArch.x64;
      case 'arm64':
        return HostArch.arm64;
      case 'armv7':
        return HostArch.armv7;
      default:
        return null;
    }
  }
}

/// Represents a host OS that can be used for building with the Android NDK.
enum HostOS {
  linux,
  macos,
  windows;

  /// Returns the string representation of this HostOS in the format used by the NDK toolchain directories
  /// (e.g. "linux", "darwin", "windows").
  @override
  String toString() {
    switch (this) {
      case HostOS.linux:
        return 'linux';
      case HostOS.macos:
        return 'darwin';
      case HostOS.windows:
        return 'windows';
    }
  }

  /// Parses a string representation of a host OS and returns the corresponding HostOS enum value.
  static HostOS? fromString(String str) {
    switch (str) {
      case 'linux':
        return HostOS.linux;
      case 'darwin':
      case 'macos':
        return HostOS.macos;
      case 'windows':
        return HostOS.windows;
      default:
        return null;
    }
  }
}

/// Represents a specific architecture of the Android NDK, such as arm64 or x86.
enum LibArch {
  arm,
  arm64,
  x86,
  riscv64,
  x86_64;

  /// Converts this LibArch to the corresponding target triple string used in the NDK sysroot library paths.
  String toTriple() {
    switch (this) {
      case LibArch.arm:
        return 'arm-linux-androideabi';
      case LibArch.arm64:
        return 'aarch64-linux-android';
      case LibArch.x86:
        return 'i686-linux-android';
      case LibArch.riscv64:
        return 'riscv64-linux-android';
      case LibArch.x86_64:
        return 'x86_64-linux-android';
    }
  }

  /// Converts this LibArch to the corresponding LLVM target triple string.
  String toLlvmTriple() {
    switch (this) {
      case LibArch.arm:
        return 'armv7-none-linux-androideabi';
      case LibArch.arm64:
        return 'aarch64-none-linux-android';
      case LibArch.x86:
        return 'i686-none-linux-android';
      case LibArch.riscv64:
        return 'riscv64-none-linux-android';
      case LibArch.x86_64:
        return 'x86_64-none-linux-android';
    }
  }

  /// Converts this LibArch to the corresponding Android ABI directory name, as
  /// used by `sources/cxx-stl/llvm-libc++/libs/` in NDK r22 and older.
  String toAbi() {
    switch (this) {
      case LibArch.arm:
        return 'armeabi-v7a';
      case LibArch.arm64:
        return 'arm64-v8a';
      case LibArch.x86:
        return 'x86';
      case LibArch.riscv64:
        return 'riscv64';
      case LibArch.x86_64:
        return 'x86_64';
    }
  }

  /// Parses a string representation of a library architecture and returns the corresponding LibArch enum value.
  static LibArch? fromString(String str) {
    switch (str) {
      case 'arm':
      case 'armeabi-v7a':
      case 'armv7':
        return LibArch.arm;
      case 'arm64':
      case 'arm64-v8a':
      case 'aarch64':
        return LibArch.arm64;
      case 'x86':
      case 'i686':
      // `Architecture.ia32` is how the Dart/Flutter build config names 32 bit
      // x86, which the NDK calls `x86` / `i686`.
      case 'ia32':
        return LibArch.x86;
      case 'riscv64':
        return LibArch.riscv64;
      case 'x86_64':
      case 'amd64':
      case 'x64':
        return LibArch.x86_64;
      default:
        return null;
    }
  }

  /// Parses a target triple string in the format used by LLVM (e.g. "armv7-none-linux-androideabi")
  /// and returns the corresponding LibArch or `null` if it cannot be parsed.
  static LibArch? fromLlvmTriple(String str) {
    switch (str) {
      case 'armv7-none-linux-androideabi':
        return LibArch.arm;
      case 'aarch64-none-linux-android':
        return LibArch.arm64;
      case 'i686-none-linux-android':
        return LibArch.x86;
      case 'riscv64-none-linux-android':
        return LibArch.riscv64;
      case 'x86_64-none-linux-android':
        return LibArch.x86_64;
      default:
        return null;
    }
  }

  /// Parses a target triple string (e.g. "arm-linux-androideabi") and returns the corresponding LibArch
  /// or `null` if it cannot be parsed.
  static LibArch? fromTriple(String str) {
    switch (str) {
      case 'arm-linux-androideabi':
        return LibArch.arm;
      case 'aarch64-linux-android':
        return LibArch.arm64;
      case 'i686-linux-android':
        return LibArch.x86;
      case 'riscv64-linux-android':
        return LibArch.riscv64;
      case 'x86_64-linux-android':
        return LibArch.x86_64;
      default:
        return null;
    }
  }
}

final class NKDVersion {
  /// NDK Major version number
  final int major;

  /// NDK Minor version number
  final int minor;

  /// NDK Patch version number
  final int patch;

  /// Optional flavor string (e.g. "beta", "rc1") for pre-release versions of the NDK.
  final String flavor;

  /// Creates an NKDVersion instance with the given major, minor, patch, and optional flavor.
  NKDVersion(this.major, this.minor, this.patch, [this.flavor = '']);

  /// Parses an NDK version string [version] in the format "major.minor.patch-flavor"
  /// and returns an NKDVersion instance.
  factory NKDVersion.parse(String version) {
    final regex = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$');
    final match = regex.firstMatch(version);
    if (match == null) {
      throw FormatException('Invalid NDK version format: $version');
    }
    return NKDVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4) ?? '',
    );
  }

  /// Compares this NKDVersion to [other] for sorting purposes.
  /// Versions are compared first by major, then minor, then patch, and finally by flavor.
  /// Flavors are compared alphabetically.
  int compareTo(NKDVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }
    return flavor.compareTo(other.flavor);
  }

  @override
  String toString() =>
      '$major.$minor.$patch${flavor.isNotEmpty ? '-$flavor' : ''}';
}

/// The ELF magic number, `0x7F` followed by `ELF`.
const _elfMagic = [0x7F, 0x45, 0x4C, 0x46];

/// Whether the file at [uri] exists and starts with the ELF magic number.
///
/// The NDK ships link-time stubs and linker scripts alongside real shared
/// objects (for example `sysroot/usr/lib/<triple>/<api>/libc++.so`, which is a
/// plain text linker script). Those must never be bundled into an application,
/// so every candidate is checked to be a real ELF object rather than merely
/// present.
bool isElfFile(Uri uri) {
  final file = File.fromUri(uri);
  if (!file.existsSync()) {
    return false;
  }
  RandomAccessFile? handle;
  try {
    handle = file.openSync();
    final magic = handle.readSync(_elfMagic.length);
    if (magic.length != _elfMagic.length) {
      return false;
    }
    for (var i = 0; i < _elfMagic.length; i++) {
      if (magic[i] != _elfMagic[i]) {
        return false;
      }
    }
    return true;
  } on FileSystemException {
    return false;
  } finally {
    handle?.closeSync();
  }
}

final class NDKApiLevel {
  /// The API level number
  final int level;

  /// The path to the sysroot library directory for this API level
  /// (e.g. "sysroot/usr/lib/arm-linux-androideabi/21/").
  final Uri sysrootLibPath;

  /// Creates an NDKApiLevel instance with the given API level and sysroot library path.
  NDKApiLevel(this.level, this.sysrootLibPath);

  @override
  String toString() => 'android-$level';
}

final class NDKTargetArchitecture {
  /// The target architecture (e.g. arm64, x86).
  final LibArch arch;

  /// The path to the sysroot library directory for this target architecture
  final Uri sysrootLibPath;
  final List<NDKApiLevel> _apiLevels;

  /// Creates an NDKTargetArchitecture instance with the given architecture, sysroot library path,
  /// and optional API levels.
  NDKTargetArchitecture(
    this.arch,
    this.sysrootLibPath, {
    List<NDKApiLevel>? apiLevels,
  }) : _apiLevels = apiLevels ?? [];

  /// Finds the highest API level that is greater than or equal to the given [minApiLevel].
  /// Returns `null` if no such API level exists.
  NDKApiLevel? highestMatching(int minApiLevel) {
    final suitableApiLevels =
        _apiLevels.where((api) => api.level >= minApiLevel).toList()
          ..sort((a, b) => b.level.compareTo(a.level));
    return suitableApiLevels.isNotEmpty ? suitableApiLevels.first : null;
  }

  void _addApiLevel(NDKApiLevel apiLevel) {
    _apiLevels.add(apiLevel);
  }

  /// The locations `libc++_shared.so` is known to live in for this target
  /// architecture, in order of preference.
  ///
  /// [ndkRoot] adds the legacy location used by NDK r22 and older, where the
  /// STL shipped under `sources/cxx-stl/` instead of inside the sysroot.
  ///
  /// Note that `sysroot/usr/lib/<triple>/<api>/libc++.so` is deliberately *not*
  /// a candidate: it is a linker script, not a shared object.
  List<Uri> libcppSharedCandidates({Uri? ndkRoot}) => [
    sysrootLibPath.resolve('libc++_shared.so'),
    if (ndkRoot != null)
      ndkRoot.resolve(
        'sources/cxx-stl/llvm-libc++/libs/${arch.toAbi()}/libc++_shared.so',
      ),
  ];

  /// Returns the first of [libcppSharedCandidates] that exists and is a real
  /// ELF shared object, or `null` if there is none.
  ///
  /// Every path that was checked is appended to [probed], so that a failure can
  /// be reported with the full list of locations that were ruled out.
  Uri? resolveLibcppShared({Uri? ndkRoot, List<Uri>? probed, Logger? logger}) {
    for (final candidate in libcppSharedCandidates(ndkRoot: ndkRoot)) {
      probed?.add(candidate);
      if (isElfFile(candidate)) {
        logger?.fine('Found libc++_shared.so at ${candidate.toFilePath()}');
        return candidate;
      }
      logger?.fine(
        'No usable libc++_shared.so at ${candidate.toFilePath()} '
        '(missing, or not an ELF shared object).',
      );
    }
    return null;
  }

  List<NDKApiLevel> get apiLevels => List.unmodifiable(_apiLevels);

  @override
  String toString() => arch.toTriple();
}

final class NDKHostArchitecture {
  /// The host OS (e.g. linux, darwin, windows).
  final HostOS os;

  /// The host architecture (e.g. x86_64, arm64).
  final HostArch arch;

  /// The path to the LLVM toolchain directory for this host architecture
  final Uri llvmToolchainPath;
  final List<NDKTargetArchitecture> _targetArchitectures;

  /// Creates an NDKHostArchitecture instance with the given OS, architecture,
  /// LLVM toolchain path, and optional target architectures.
  NDKHostArchitecture(
    this.os,
    this.arch,
    this.llvmToolchainPath, {
    List<NDKTargetArchitecture>? targetArchitectures,
  }) : _targetArchitectures = targetArchitectures ?? [];

  /// Finds the target architecture info for the given [targetArch], or `null` if not found.
  NDKTargetArchitecture? findTarget(LibArch targetArch) {
    try {
      return _targetArchitectures.firstWhere((t) => t.arch == targetArch);
    } catch (e) {
      return null;
    }
  }

  void _addTargetArchitecture(NDKTargetArchitecture targetArch) {
    _targetArchitectures.add(targetArch);
  }

  List<NDKTargetArchitecture> get targetArchitectures =>
      List.unmodifiable(_targetArchitectures);

  @override
  String toString() => '$os-$arch';
}

final class NDKInfo {
  /// The path to the root directory of the NDK installation.
  final Uri path;

  /// The version of the NDK.
  final NKDVersion version;
  final List<NDKHostArchitecture> hostArchitectures;

  /// Creates an NDKInfo instance with the given path, version, and host architectures.
  NDKInfo({
    required this.path,
    required this.version,
    required this.hostArchitectures,
  });

  /// Finds the host architecture info for the given [hostOS], or `null` if not found.
  NDKHostArchitecture? findHost(HostOS hostOS) {
    try {
      return hostArchitectures.firstWhere((h) => h.os == hostOS);
    } catch (e) {
      return null;
    }
  }
}

class NDKLocator {
  /// Well known SDK installation roots. Each is expanded to both `ndk/*` and
  /// `ndk-bundle` when searching for NDK installations.
  static final _sdkSearchPaths = [
    if (Platform.isLinux) ...[
      '\$HOME/.androidsdkroot/', // Firebase Studio
      '\$HOME/Android/Sdk/',
      '\$HOME/.local/share/Android/Sdk/',
      '/opt/android-sdk/',
      '/usr/lib/android-sdk/',
    ],
    if (Platform.isMacOS) ...[
      '\$HOME/Library/Android/sdk/',
      '/usr/local/share/android-sdk/',
      '/opt/homebrew/share/android-commandlinetools/',
    ],
    if (Platform.isWindows) ...['\$HOME/AppData/Local/Android/Sdk/'],
  ];

  static final _ndkEnvVars = [
    'ANDROID_NDK',
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_LATEST_HOME',
    'ANDROID_NDK_ROOT',
  ];

  static final _androidHomeEnvVars = [
    'ANDROID_HOME',
    'ANDROID_SDK_ROOT',
    'ANDROID_SDK_HOME',
  ];

  static final _pathExe = Platform.isWindows ? 'ndk-build.cmd' : 'ndk-build';

  /// The user's home directory, or `null` if it is not set in the environment.
  ///
  /// Windows uses `USERPROFILE` (`HOME` is set by PowerShell but not by
  /// `cmd.exe`), and its separators are normalised to `/` because that is what
  /// [Glob] requires.
  static String? homeDirectory() => Platform.isWindows
      ? Platform.environment['USERPROFILE']?.replaceAll('\\', '/')
      : Platform.environment['HOME'];

  /// Replaces `$HOME` in [pathTemplate] with the user's home directory.
  static String expandHome(String pathTemplate) {
    if (!pathTemplate.contains('\$HOME')) {
      return pathTemplate;
    }
    final home = homeDirectory();
    if (home == null) {
      throw Exception(
        'Failed to find home directory. Please ensure that the HOME environment variable is set. On Windows, the USERPROFILE environment variable should be set instead.',
      );
    }
    return pathTemplate.replaceAll('\$HOME', home);
  }

  /// Expands a path template with environment variables and glob patterns.
  static List<FileSystemEntity> expandPath(String pathTemplate) {
    final glob = Glob(expandHome(pathTemplate));
    final matches = glob.listSync();
    return matches;
  }

  /// Returns the directory [path] as a `Uri` with a trailing slash, or `null`
  /// if it does not exist.
  ///
  /// This treats [path] as a literal, so paths containing
  /// glob metacharacters (`[`, `{`, `,`, ...) are handled correctly. Use this
  /// for values that come from the environment or a properties file, and
  /// [expandPath] for the `*` templates defined in this class.
  static Uri? _existingDir(String path) {
    if (path.trim().isEmpty) {
      return null;
    }
    final dir = Directory(path.trim());
    return dir.existsSync() ? dir.uri : null;
  }

  /// Returns the NDK installations under an SDK root: every `ndk/<version>/`
  /// directory plus the legacy `ndk-bundle/` directory.
  static List<Uri> _ndkDirsInSdkRoot(Uri sdkRoot) {
    final ndkDirs = <Uri>[];
    final versioned = Directory.fromUri(sdkRoot.resolve('ndk/'));
    if (versioned.existsSync()) {
      for (final entry in versioned.listSync().whereType<Directory>()) {
        ndkDirs.add(entry.uri);
      }
    }
    final bundle = _existingDir(
      Directory.fromUri(sdkRoot.resolve('ndk-bundle/')).path,
    );
    if (bundle != null) {
      ndkDirs.add(bundle);
    }
    return ndkDirs;
  }

  /// Reads `sdk.dir` and `ndk.dir` from the `local.properties` of the Flutter
  /// or Gradle project being built, if one can be found.
  ///
  /// [projectRoot] is the application directory; both `local.properties` and
  /// `android/local.properties` are checked. This is the location Flutter and
  /// Gradle themselves use, so it is authoritative when it is present, but it
  /// is entirely optional - everything here is best effort.
  static ({Uri? sdkDir, Uri? ndkDir}) readLocalProperties(
    Uri projectRoot, {
    Logger? logger,
  }) {
    for (final relative in const [
      'local.properties',
      'android/local.properties',
    ]) {
      final file = File.fromUri(projectRoot.resolve(relative));
      if (!file.existsSync()) {
        continue;
      }
      logger?.fine('Reading ${file.path}');
      final props = <String, String>{};
      for (final line in LineSplitter.split(file.readAsStringSync())) {
        final trimmed = line.trim();
        if (trimmed.startsWith('#')) {
          continue;
        }
        final separator = trimmed.indexOf('=');
        if (separator > 0) {
          props[trimmed.substring(0, separator).trim()] = trimmed
              .substring(separator + 1)
              .trim();
        }
      }
      final sdkDir = props['sdk.dir'];
      final ndkDir = props['ndk.dir'];
      if (sdkDir != null || ndkDir != null) {
        return (
          sdkDir: sdkDir == null ? null : _existingDir(sdkDir),
          ndkDir: ndkDir == null ? null : _existingDir(ndkDir),
        );
      }
    }
    return (sdkDir: null, ndkDir: null);
  }

  /// Reads the `android-sdk` setting written by `flutter config --android-sdk`
  /// from `~/.flutter_settings`, or `null` if it is not set.
  static Uri? readFlutterSettingsSdk({Logger? logger}) {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home == null) {
      return null;
    }
    final settings = File.fromUri(
      Directory(home).uri.resolve('.flutter_settings'),
    );
    if (!settings.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(settings.readAsStringSync());
      if (decoded is Map && decoded['android-sdk'] is String) {
        return _existingDir(decoded['android-sdk'] as String);
      }
    } catch (e) {
      logger?.fine('Could not read ${settings.path}: $e');
    }
    return null;
  }

  /// Returns the root of the NDK that [compiler] (the NDK `clang` reported in
  /// the build config by the Flutter tool) belongs to, or `null` if it does not
  /// look like an NDK toolchain path.
  ///
  /// The layout is `<ndk>/toolchains/llvm/prebuilt/<host tag>/bin/clang`, so
  /// this identifies both the exact NDK and the exact host tag the rest of the
  /// build is using, which no environment scan can guarantee.
  static Uri? ndkRootFromCompiler(Uri compiler) {
    final ndkRoot = compiler.resolve('../../../../../');
    final segments = compiler.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length < 6) {
      return null;
    }
    final expected = segments.sublist(segments.length - 6, segments.length - 2);
    if (expected[0] != 'toolchains' ||
        expected[1] != 'llvm' ||
        expected[2] != 'prebuilt') {
      return null;
    }
    return _existingDir(Directory.fromUri(ndkRoot).path);
  }

  static Future<NDKInfo> _getNDKInfo(Uri ndkPath, {Logger? logger}) async {
    // Add a trailing slash to make sure that relative paths resolve correctly.
    if (!ndkPath.path.endsWith('/')) {
      ndkPath = ndkPath.replace(path: '${ndkPath.path}/');
    }
    final sourceProps = File.fromUri(ndkPath.resolve('source.properties'));
    if (!sourceProps.existsSync()) {
      throw Exception(
        'NDK at ${ndkPath.toFilePath()} is missing source.properties',
      );
    }
    final propsContent = await sourceProps.readAsString();
    final props = <String, String>{};
    for (final line in LineSplitter.split(propsContent)) {
      final parts = line.split('=');
      if (parts.length == 2) {
        props[parts[0].trim()] = parts[1].trim();
      }
    }
    final versionStr = props['Pkg.Revision'];
    if (versionStr == null) {
      throw Exception(
        'NDK at ${ndkPath.toFilePath()} is missing Pkg.Revision in source.properties',
      );
    }
    final version = NKDVersion.parse(versionStr);

    // The toolchains directory contain subdirectories for each host arch
    final toolchainsDir = Directory.fromUri(
      ndkPath.resolve('toolchains/llvm/prebuilt/'),
    );
    if (!toolchainsDir.existsSync()) {
      throw Exception(
        'NDK at ${ndkPath.toFilePath()} is missing toolchains directory',
      );
    }
    final hostArchitectures = <NDKHostArchitecture>[];
    for (final hostDir in toolchainsDir.listSync().whereType<Directory>()) {
      logger?.fine('Checking host directory: ${hostDir.uri.toFilePath()}');
      final hostName = hostDir.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      final parts = hostName.split('-');
      if (parts.length >= 2) {
        final osPart = parts[0];
        final archPart = parts.sublist(1).join('-');
        final os = HostOS.fromString(osPart);
        final arch = HostArch.fromString(archPart);
        if (os != null && arch != null) {
          hostArchitectures.add(NDKHostArchitecture(os, arch, hostDir.uri));
        }
      }
    }

    // The host arch directory contains
    // sysroot/usr/lib/<target arch> directories for each target arch
    for (final host in hostArchitectures) {
      final sysrootLibDir = Directory.fromUri(
        host.llvmToolchainPath.resolve('sysroot/usr/lib/'),
      );
      if (sysrootLibDir.existsSync()) {
        for (final targetDir
            in sysrootLibDir.listSync().whereType<Directory>()) {
          final targetName = targetDir.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
          );
          final targetArch = LibArch.fromTriple(targetName);
          if (targetArch != null) {
            host._addTargetArchitecture(
              NDKTargetArchitecture(targetArch, targetDir.uri),
            );
          }
        }
      }
    }

    // The target arch lib directories contain subdirectories for each API level
    // e.g. sysroot/usr/lib/arm-linux-androideabi/21/
    for (final host in hostArchitectures) {
      for (final target in host.targetArchitectures) {
        final targetLibDir = Directory.fromUri(target.sysrootLibPath);
        if (targetLibDir.existsSync()) {
          for (final apiLevelDir
              in targetLibDir.listSync().whereType<Directory>()) {
            final apiLevelName = apiLevelDir.uri.pathSegments.lastWhere(
              (segment) => segment.isNotEmpty,
            );
            final apiLevelNum = int.tryParse(apiLevelName);
            if (apiLevelNum != null) {
              target._addApiLevel(NDKApiLevel(apiLevelNum, apiLevelDir.uri));
            }
          }
        }
      }
    }

    return NDKInfo(
      path: ndkPath,
      version: version,
      hostArchitectures: hostArchitectures,
    );
  }

  /// Returns every usable Android NDK installation that could be found.
  ///
  /// [projectRoot], when given, is the root of the application being built and
  /// enables reading `sdk.dir` / `ndk.dir` from its `local.properties`.
  /// [extraNdkPaths] are tried before anything that is discovered, and are
  /// intended for NDK roots that are already known (such as the one the Flutter
  /// tool reported in the build config).
  static Future<List<NDKInfo>> locate({
    Logger? logger,
    Uri? projectRoot,
    Iterable<Uri> extraNdkPaths = const [],
  }) async {
    final ndkPaths = <Uri>{};
    final sdkRoots = <Uri>{};

    void addNdkPath(Uri? path, String source) {
      if (path == null) {
        return;
      }
      if (ndkPaths.add(path)) {
        logger?.fine('NDK candidate from $source: ${path.toFilePath()}');
      }
    }

    void addSdkRoot(Uri? root, String source) {
      if (root == null) {
        return;
      }
      if (sdkRoots.add(root)) {
        logger?.fine('SDK root from $source: ${root.toFilePath()}');
      }
    }

    ndkPaths.addAll(extraNdkPaths);

    // first see if the exe is in path using which
    final whichResult = await which(_pathExe);
    if (whichResult != null) {
      // `ndk-build` sits in the root of the NDK, so the directory containing it
      // is the NDK root. Resolving against a file Uri already drops the file
      // name, so `./` is the containing directory and `../` would be its
      // parent.
      final ndkDir = whichResult.resolve('./');
      if (ndkDir.toFilePath() != whichResult.toFilePath()) {
        addNdkPath(ndkDir, 'ndk-build on PATH');
      }
    }

    // then check environment variables
    for (final envVar in _ndkEnvVars) {
      final envValue = Platform.environment[envVar];
      if (envValue != null) {
        addNdkPath(_existingDir(envValue), '\$$envVar');
      }
    }

    // the project's own local.properties is what Flutter and Gradle use
    if (projectRoot != null) {
      final localProperties = readLocalProperties(projectRoot, logger: logger);
      addNdkPath(localProperties.ndkDir, 'ndk.dir in local.properties');
      addSdkRoot(localProperties.sdkDir, 'sdk.dir in local.properties');
    }

    // SDK roots from the environment, from `flutter config --android-sdk`, and
    // from the well known installation locations
    for (final envVar in _androidHomeEnvVars) {
      final envValue = Platform.environment[envVar];
      if (envValue != null) {
        addSdkRoot(_existingDir(envValue), '\$$envVar');
      }
    }
    addSdkRoot(readFlutterSettingsSdk(logger: logger), '~/.flutter_settings');
    for (final pathTemplate in _sdkSearchPaths) {
      try {
        addSdkRoot(
          _existingDir(expandHome(pathTemplate)),
          'well known install location',
        );
      } catch (e) {
        logger?.fine('Could not expand $pathTemplate: $e');
      }
    }

    for (final sdkRoot in sdkRoots) {
      for (final ndkDir in _ndkDirsInSdkRoot(sdkRoot)) {
        addNdkPath(ndkDir, 'SDK root ${sdkRoot.toFilePath()}');
      }
    }

    final List<NDKInfo> ndkInfos = [];
    for (final ndkPath in ndkPaths) {
      try {
        final info = await _getNDKInfo(ndkPath, logger: logger);
        ndkInfos.add(info);
      } catch (e, st) {
        // ignore invalid NDK directories
        logger?.warning(
          'Warning: Failed to get info for NDK at ${ndkPath.toFilePath()}: $e',
        );
        logger?.fine('Stack trace: $st');
      }
    }
    return ndkInfos;
  }
}

/// Extension method to find the best matching NDKInfo for a given BuildConfig.
/// This will return the NDKInfo with the highest version that supports the target
/// architecture and minimum API level specified in the BuildConfig.
extension FindNDKInfo on Iterable<NDKInfo> {
  /// Finds every NDK that can supply libraries for [config], highest version
  /// first.
  ///
  /// Each returned [NDKInfo] is filtered down to the matching host, target
  /// architecture and API level. More than one is returned so that a caller can
  /// move on to the next NDK when the highest versioned one turns out to be
  /// incomplete.
  List<NDKInfo> allForBuildConfig(BuildConfig config, {Logger? logger}) {
    final sorted = toList()..sort((a, b) => b.version.compareTo(a.version));
    final hostOS = HostOS.fromString(Platform.operatingSystem);
    if (hostOS == null) {
      logger?.warning(
        'Unsupported host OS for the Android NDK: ${Platform.operatingSystem}.',
      );
      return [];
    }
    final targetArchName = config.code.targetArchitecture.toString();
    final targetArch = LibArch.fromString(targetArchName);
    if (targetArch == null) {
      logger?.warning(
        'The Android NDK has no libraries for target architecture '
        '$targetArchName.',
      );
      return [];
    }
    final minApiLevel = config.code.android.targetNdkApi;
    final matches = <NDKInfo>[];
    for (final ndk in sorted) {
      final host = ndk.findHost(hostOS);
      if (host == null) {
        logger?.fine(
          'NDK ${ndk.version} at ${ndk.path.toFilePath()} has no $hostOS host '
          'toolchain.',
        );
        continue;
      }
      final target = host.findTarget(targetArch);
      if (target == null) {
        logger?.fine(
          'NDK ${ndk.version} at ${ndk.path.toFilePath()} has no '
          '${targetArch.toTriple()} libraries.',
        );
        continue;
      }
      final apiLevel = target.highestMatching(minApiLevel);
      if (apiLevel == null) {
        logger?.fine(
          'NDK ${ndk.version} at ${ndk.path.toFilePath()} does not support API '
          'level $minApiLevel for ${targetArch.toTriple()}.',
        );
        continue;
      }
      // Add the filtered version.
      matches.add(
        NDKInfo(
          path: ndk.path,
          version: ndk.version,
          hostArchitectures: [
            NDKHostArchitecture(
              host.os,
              host.arch,
              host.llvmToolchainPath,
              targetArchitectures: [
                NDKTargetArchitecture(
                  target.arch,
                  target.sysrootLibPath,
                  apiLevels: [apiLevel],
                ),
              ],
            ),
          ],
        ),
      );
    }
    return matches;
  }

  /// Finds the best matching NDKInfo for the given [config], or `null` if no suitable NDK is found.
  NDKInfo? forBuildConfig(BuildConfig config, {Logger? logger}) =>
      allForBuildConfig(config, logger: logger).firstOrNull;
}
