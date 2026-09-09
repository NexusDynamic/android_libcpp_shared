import 'package:android_libcpp_shared/src/locate_ndk.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  final logger = Logger('AndroidLibcppSharedHook')
    ..onRecord.listen((record) {
      print('${record.level.name}: ${record.message}');
    });

  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final targetOs = input.config.code.targetOS;
    if (targetOs != OS.android) {
      logger.info(
        'Target OS is $targetOs, skipping Android system library inclusion.',
      );
      return;
    }

    final Architecture targetArchitecture =
        input.config.code.targetArchitecture;

    logger.info('Searching for android NDK...');
    final ndkPaths = await NDKLocator.locate(
      logger: logger,
      config: input.config,
    );
    final ndk = ndkPaths.forBuildConfig(input.config);
    if (ndk == null) {
      throw StateError(
        'No suitable NDK found for target architecture $targetArchitecture.',
      );
    }
    logger.info('Found NDK at ${ndk.path}, version ${ndk.version}.');
    final libcppSharedPath = ndk
        .hostArchitectures
        .first
        .targetArchitectures
        .first
        .sysrootLibPath
        .resolve('libc++_shared.so');

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'libc++_shared.so',
        file: libcppSharedPath,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}
