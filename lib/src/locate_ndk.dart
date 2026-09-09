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
  static final _searchPaths = [
    if (Platform.isLinux) ...[
      r'$HOME/.androidsdkroot/ndk/*/', // Firebase Studio
      r'$HOME/Android/Sdk/ndk/*/',
      r'$HOME/Android/Sdk/ndk-bundle/',
      r'$HOME/android-sdk/ndk/*/',
      r'$HOME/android-sdk/ndk-bundle/',
      r'$HOME/Android/sdk/ndk/*/',
      r'$HOME/Android/sdk/ndk-bundle/',
      '/usr/lib/android-sdk/ndk/*/',
      '/opt/android-sdk/ndk/*/',
      '/opt/android/ndk/*/',
      '/usr/local/android-sdk/ndk/*/',
    ],
    if (Platform.isMacOS) ...[
      r'$HOME/Library/Android/sdk/ndk/*/',
      r'$HOME/Library/Android/sdk/ndk-bundle/',
      r'$HOME/Library/Android/Sdk/ndk/*/',
      r'$HOME/Library/Android/Sdk/ndk-bundle/',
    ],
    if (Platform.isWindows) ...[
      r'$HOME/AppData/Local/Android/Sdk/ndk/*/',
      r'$HOME/AppData/Local/Android/Sdk/ndk-bundle/',
      r'$HOME/AppData/Local/Android/sdk/ndk/*/',
      r'$HOME/AppData/Local/Android/sdk/ndk-bundle/',
    ],
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

  /// Expands a path template with environment variables and glob patterns.
  static List<FileSystemEntity> expandPath(String pathTemplate) {
    // Use platform-dependent environment variables for the user's home directory
    final homeDir = Platform.isWindows
        ? Platform.environment['USERPROFILE'] ?? ''
        : Platform.environment['HOME'] ?? '';
    if (homeDir.isEmpty && pathTemplate.startsWith(r'$HOME')) {
      return const [];
    }
    // Glob requires forward slashes, and USERPROFILE uses backslashes
    final normalizedHomeDir = homeDir.replaceAll('\\', '/');
    final path = pathTemplate.replaceAll(r'$HOME', normalizedHomeDir);
    if (!path.contains('*') && !path.contains('?')) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        return [dir];
      }
      return const [];
    }
    try {
      final glob = Glob(path);
      final matches = glob.listSync();
      return matches;
    } catch (_) {
      return const [];
    }
  }

  /// Attempts to locate the NDK root directory from a compiler toolchain URI
  /// (e.g. clang, ld, ar).
  static Uri? findNdkFromTool(Uri toolUri) {
    try {
      var dir = Directory(toolUri.toFilePath());
      for (var i = 0; i < 8; i++) {
        if (dir.path == dir.parent.path) break;
        dir = dir.parent;
        final sep = Platform.pathSeparator;
        final normPath = dir.path.endsWith(sep) ? dir.path : '${dir.path}$sep';
        final sourceProps = File('${normPath}source.properties');
        final toolchains = Directory('${normPath}toolchains');
        if (sourceProps.existsSync() && toolchains.existsSync()) {
          return dir.uri;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Attempts to find NDK or SDK paths specified in `local.properties` files.
  static List<Uri> findNdksFromLocalProperties() {
    final results = <Uri>[];
    final sep = Platform.pathSeparator;
    final searchDirs = <Directory>[
      Directory.current,
      Directory('${Directory.current.path}${sep}android'),
    ];
    var parent = Directory.current;
    for (var i = 0; i < 5; i++) {
      if (parent.path == parent.parent.path) break;
      parent = parent.parent;
      searchDirs.add(parent);
      searchDirs.add(Directory('${parent.path}${sep}android'));
    }
    for (final dir in searchDirs) {
      final lp = File('${dir.path}${sep}local.properties');
      if (lp.existsSync()) {
        try {
          final lines = lp.readAsLinesSync();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('#')) continue;
            final eq = trimmed.indexOf('=');
            if (eq > 0) {
              final key = trimmed.substring(0, eq).trim();
              var value = trimmed.substring(eq + 1).trim();
              value = value.replaceAll(r'\:', ':').replaceAll(r'\\', r'\');
              if (key == 'ndk.dir') {
                final d = Directory(value);
                if (d.existsSync()) results.add(d.uri);
              } else if (key == 'sdk.dir') {
                final sdkDir = Directory(value);
                if (sdkDir.existsSync()) {
                  final ndkSub = Directory('${sdkDir.path}${sep}ndk');
                  if (ndkSub.existsSync()) {
                    for (final ent in ndkSub.listSync().whereType<Directory>()) {
                      results.add(ent.uri);
                    }
                  }
                  final bundle = Directory('${sdkDir.path}${sep}ndk-bundle');
                  if (bundle.existsSync()) {
                    results.add(bundle.uri);
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    }
    return results;
  }

  static Future<NDKInfo> _getNDKInfo(Uri ndkPath, {Logger? logger}) async {
    final ndkFilePath = ndkPath.toFilePath();
    final sep = Platform.pathSeparator;
    final normalizedNdkPath = ndkFilePath.endsWith(sep)
        ? ndkFilePath
        : '$ndkFilePath$sep';

    final sourceProps = File('${normalizedNdkPath}source.properties');
    if (!sourceProps.existsSync()) {
      throw Exception(
        'NDK at $normalizedNdkPath is missing source.properties',
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
        'NDK at $normalizedNdkPath is missing Pkg.Revision in source.properties',
      );
    }
    final version = NKDVersion.parse(versionStr);

    // The toolchains directory contain subdirectories for each host arch
    final toolchainsDir = Directory(
      '${normalizedNdkPath}toolchains${sep}llvm${sep}prebuilt$sep',
    );
    if (!toolchainsDir.existsSync()) {
      throw Exception(
        'NDK at $normalizedNdkPath is missing toolchains directory',
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
      final sysrootLibDir = Directory(
        '${host.llvmToolchainPath.toFilePath()}${sep}sysroot${sep}usr${sep}lib$sep',
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
        final targetLibDir = Directory(
          '${target.sysrootLibPath.toFilePath()}$sep',
        );
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

  /// Returns the path to the Android NDK, or `null` if it cannot be found.
  static Future<List<NDKInfo>> locate({
    Logger? logger,
    BuildConfig? config,
  }) async {
    final ndkPaths = <Uri>{};

    // 0. First check if a compiler is specified in the BuildConfig
    if (config != null) {
      final cCompiler = config.code.cCompiler;
      if (cCompiler != null) {
        for (final toolUri in [
          cCompiler.compiler,
          cCompiler.archiver,
          cCompiler.linker,
        ]) {
          if (toolUri != null) {
            final ndk = findNdkFromTool(toolUri);
            if (ndk != null) {
              logger?.info(
                'Found NDK from compiler config: ${ndk.toFilePath()}',
              );
              ndkPaths.add(ndk);
              break;
            }
          }
        }
      }
    }

    // 1. Check local.properties in current and parent directories
    for (final ndkUri in findNdksFromLocalProperties()) {
      ndkPaths.add(ndkUri);
    }

    // 2. See if the exe is in path using which
    final whichResult = await which(_pathExe);
    if (whichResult != null) {
      final ndkDir = whichResult.resolve('../');
      if (ndkDir.toFilePath() != whichResult.toFilePath()) {
        ndkPaths.add(ndkDir);
      }
    }

    // 3. Check environment variables
    for (final envVar in _ndkEnvVars) {
      final envValue = Platform.environment[envVar]?.trim();
      if (envValue != null && envValue.isNotEmpty) {
        final ndkDir = Directory(envValue);
        if (ndkDir.existsSync()) {
          final sep = Platform.pathSeparator;
          if (File('${ndkDir.path}${sep}source.properties').existsSync()) {
            ndkPaths.add(ndkDir.uri);
          } else {
            for (final match in ndkDir.listSync().whereType<Directory>()) {
              if (File('${match.path}${sep}source.properties').existsSync()) {
                ndkPaths.add(match.uri);
              }
            }
          }
        }
      }
    }

    // 4. Finally, if we have an ANDROID_HOME / ANDROID_SDK_ROOT, check for the NDK there
    for (final envVar in _androidHomeEnvVars) {
      final envValue = Platform.environment[envVar]?.trim();
      if (envValue != null && envValue.isNotEmpty) {
        final sdkDir = Directory(envValue);
        if (sdkDir.existsSync()) {
          final sep = Platform.pathSeparator;
          final ndkDir = Directory('${sdkDir.path}${sep}ndk');
          if (ndkDir.existsSync()) {
            for (final entry in ndkDir.listSync().whereType<Directory>()) {
              ndkPaths.add(entry.uri);
            }
          }
          final ndkBundle = Directory('${sdkDir.path}${sep}ndk-bundle');
          if (ndkBundle.existsSync()) {
            ndkPaths.add(ndkBundle.uri);
          }
        }
      }
    }

    // 5. Try common install locations
    for (final pathTemplate in _searchPaths) {
      for (final match in expandPath(pathTemplate)) {
        if (match is Directory) {
          ndkPaths.add(match.uri);
        }
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
  /// Finds the best matching NDKInfo for the given [config], or `null` if no suitable NDK is found.
  NDKInfo? forBuildConfig(BuildConfig config) {
    // If a compiler was specified, try to find the NDK that matches the compiler's path first
    final compiler = config.code.cCompiler?.compiler;
    final compilerNdkUri =
        compiler != null ? NDKLocator.findNdkFromTool(compiler) : null;

    final sorted = toList()..sort((a, b) {
      if (compilerNdkUri != null) {
        if (a.path == compilerNdkUri) return -1;
        if (b.path == compilerNdkUri) return 1;
      }
      return b.version.compareTo(a.version);
    });

    final hostOS = HostOS.fromString(Platform.operatingSystem);
    final targetArch = LibArch.fromString(
      config.code.targetArchitecture.toString(),
    );
    final minApiLevel = config.code.android.targetNdkApi;
    for (final ndk in sorted) {
      final host = ndk.findHost(hostOS!);
      if (host != null) {
        final target = host.findTarget(targetArch!);
        if (target != null) {
          final apiLevel = target.highestMatching(minApiLevel) ??
              (target.apiLevels.isNotEmpty
                  ? target.apiLevels.first
                  : NDKApiLevel(minApiLevel, target.sysrootLibPath));

          // Ensure libc++_shared.so actually exists
          final libcppFile = File.fromUri(
            target.sysrootLibPath.resolve('libc++_shared.so'),
          );
          if (libcppFile.existsSync()) {
            // Return the filtered version.
            return NDKInfo(
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
            );
          }
        }
      }
    }
    return null;
  }
}
