# android_libcpp_shared

Dart / flutter package for Android to add the libc++_shared.so STL C++ shared runtime library to your app

# Usage

## Prerequisites

You obviously need dart/flutter installed, but in addition you must have the Android NDK installed. This package does its best to find the NDK install location during the build hook step.

## Adding the dependency

Add the package to your pubspec.yaml dependencies:

```yaml
dependencies:
  android_libcpp_shared: ^0.1.0
```

You don't need to import anything into your Dart code, the dependency is sufficient to bundle the native library with your app. The package does include an optional API if you want to directly use functions from `libc++_shared.so` using `dart:ffi`, but this is not required to include the library in your app.

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
