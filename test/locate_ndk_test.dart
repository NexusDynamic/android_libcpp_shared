import 'dart:io';
import 'package:test/test.dart';
import 'package:android_libcpp_shared/src/locate_ndk.dart';

void main() {
  test('locate returns non-empty set of paths', () async {
    final ndkPaths = await NDKLocator.locate();
    expect(ndkPaths, isNotEmpty);
  });

  test('findNdkFromTool finds NDK from toolchain path', () async {
    final ndkPaths = await NDKLocator.locate();
    if (ndkPaths.isNotEmpty) {
      final ndk = ndkPaths.first;
      final clangUri = ndk.path.resolve(
        'toolchains/llvm/prebuilt/linux-x86_64/bin/clang',
      );
      if (File(clangUri.toFilePath()).existsSync()) {
        final found = NDKLocator.findNdkFromTool(clangUri);
        expect(found, isNotNull);
        expect(found!.toFilePath(), equals(ndk.path.toFilePath()));
      }
    }
  });

  test('locate finds NDK even if environment variables are missing', () async {
    final ndkPaths = await NDKLocator.locate();
    for (final info in ndkPaths) {
      expect(info.version.major, isPositive);
      expect(info.hostArchitectures, isNotEmpty);
    }
  });
}
