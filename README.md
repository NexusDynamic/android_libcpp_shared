# android_libcpp_shared

[![Pub Publisher](https://img.shields.io/pub/publisher/android_libcpp_shared?style=flat-square)](https://pub.dev/publishers/zeyus.com/packages) [![Pub Version](https://img.shields.io/pub/v/android_libcpp_shared)](https://pub.dev/packages/android_libcpp_shared) 

Dart / flutter package for Android to add the libc++_shared.so STL C++ shared runtime library to your app

# Usage

## Prerequisites

You obviously need dart/flutter installed, but in addition you must have the Android NDK installed. This package does its best to find the NDK install location during the build hook step.

### How the library is found

During the build hook, `libc++_shared.so` is looked for in this order:

1. An explicit override, if you have set one (see [Overriding the location](#overriding-the-location)).
2. The NDK that the Flutter tool itself is building with, derived from the compiler in the build config.
3. Every other NDK installation that can be found, highest version first. These come from `ndk-build` on your `PATH`, the `ANDROID_NDK`, `ANDROID_NDK_HOME`, `ANDROID_NDK_LATEST_HOME` and `ANDROID_NDK_ROOT` environment variables, `sdk.dir` / `ndk.dir` in your project's `local.properties`, the `ANDROID_HOME`, `ANDROID_SDK_ROOT` and `ANDROID_SDK_HOME` environment variables, `flutter config --android-sdk`, and the usual installation directories for your platform.

A candidate is only used once it has been verified to exist and to be an ELF shared object, so an incomplete NDK installation is skipped in favour of the next one rather than producing a build that fails later. If nothing usable is found the build hook fails with the full list of NDKs considered and files checked - please include that output when reporting an issue.

### Overriding the location

If the library lives somewhere this package does not look, point it at the file directly in your application's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    android_libcpp_shared:
      libcpp_shared_path: /path/to/libc++_shared.so
```

The `ANDROID_LIBCPP_SHARED_PATH` environment variable does the same thing. Note that Gradle reuses a long lived daemon, so a variable exported after the daemon started will not reach the build hook; the user define is not affected by that.

Both settings also accept the root of an NDK installation, in which case that NDK is used in preference to any other.

## Adding the dependency

Add the package to your pubspec.yaml dependencies:

```yaml
dependencies:
  android_libcpp_shared: ^0.2.0
```

You don't need to import anything into your Dart code, the dependency is sufficient to bundle the native library with your app. The package does include an optional API if you want to directly use functions from `libc++_shared.so` using `dart:ffi`, but this is not required to include the library in your app.

### Gradle configuration

Consider adding `--enable-native-access=ALL-UNNAMED` to `org.gradle.jvmargs` in your `gradle.properties` file. This will help make sure that future versions of gradle / java won't break with restrictod methods.

Your entire `android/gradle.properties` file should look something like this (along with any additional properties you have added):

```gradle
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError --enable-native-access=ALL-UNNAMED
android.useAndroidX=true
# This builtInKotlin flag was added automatically by Flutter migrator
android.builtInKotlin=false
# This newDsl flag was added automatically by Flutter migrator
android.newDsl=false
```

Once Flutter has migrated to a newer gradle / android gradle plugin version, these instructions may change.

## Optional API

If you want to directly use functions from `libc++_shared.so` using `dart:ffi`, you can use API like this:

```dart
import 'package:android_libcpp_shared/android_libcpp_shared.dart';

void main() {
  // Example usage of the API to call a function from libc++_shared.so
  final int Function()? nativeRand = libCppShared?.lookup<ffi.NativeFunction<ffi.Int64 Function()>>('rand')
          .asFunction<int Function()>();
  if (nativeRand == null) {
    print('You are not on android');
    return;
  }
  final result = nativeRand();
  print('Random number from libc++_shared.so: $result');
}
```

# License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
Parts of the NDK locating code are adapted from the Dart native_toolchain_c package, which is licensed under a BSD-style license. See the [NATIVE_LICENSE](NATIVE_LICENSE) file for details.
