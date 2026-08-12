import 'package:android_libcpp_shared/src/resolve_libcpp.dart';
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

    logger.info('Searching for libc++_shared.so for $targetArchitecture...');
    final resolution = await resolveLibcppShared(input, logger: logger);
    final libcppSharedPath = resolution.libcppShared;
    if (libcppSharedPath == null) {
      throw StateError(
        resolution.describeFailure(
          targetArchitecture,
          input.config.code.android.targetNdkApi,
        ),
      );
    }
    final ndk = resolution.ndk;
    if (ndk != null) {
      logger.info('Using NDK ${ndk.version} at ${ndk.path.toFilePath()}.');
    }
    logger.info('Using ${libcppSharedPath.toFilePath()}.');

    // Re-run the hook if the library path changes
    output.dependencies.add(libcppSharedPath);

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
