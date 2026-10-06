import 'dart:io';

import 'package:android_libcpp_shared/src/resolve_libcpp.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('libcpp_hook_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('bundles a copy in the output directory, not the source', () async {
    final source = File('${tempDir.path}/libc++_shared.so')
      ..writeAsBytesSync([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00]);

    await testBuildHook(
      mainMethod: hook.main,
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.arm64,
          targetOS: OS.android,
          linkModePreference: LinkModePreference.dynamic,
          android: AndroidCodeConfig(targetNdkApi: 21),
        ),
      ],
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {libcppSharedPathUserDefine: source.path},
          basePath: tempDir.uri,
        ),
      ),
      check: (input, output) {
        final asset = output.assets.code.single;
        final bundled = File.fromUri(asset.file!);
        final outputDirectory = Directory.fromUri(input.outputDirectory);
        expect(bundled.path, startsWith(outputDirectory.path));
        expect(bundled.readAsBytesSync(), source.readAsBytesSync());

        bundled.deleteSync();
        expect(source.existsSync(), isTrue);
      },
    );
  });
}
