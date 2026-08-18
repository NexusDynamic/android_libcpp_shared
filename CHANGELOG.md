# Changelog

## 0.3.0

* Updated example to not use the kotlin gradle plugin (removing the warning when building the example)
* **BREAKING**: Updated the `code_assets` dependency to `^2.0.0`, see [code_assets changelog](https://pub.dev/packages/code_assets/changelog#200)
* Updated `hooks` to `^2.2.0`
* Updated `native_toolchain_c` to `^0.19.4`
* Updated `test` dev dependency to  `^1.31.2`

## 0.2.1

* Fixed NDK path resolution on Windows by using `USERPROFILE` and normalizing path separators. Thanks @kekland and @AttalliAyoub for the PRs and Issue (#2).
* Fixed `runProcess` failing with a `FormatException` on non-English Windows by decoding process output with the system encoding. Thanks @wyq0918dev for the PR / Issue (#4).
* The build hook now verifies that `libc++_shared.so` exists and is an ELF shared object before emitting it: thanks to @chillbrodev for the Issue (#5).
* An NDK that does not contain the library for the target architecture is now skipped in favour of the next installation, instead of failing the build.
* Added the legacy `sources/cxx-stl/llvm-libc++/libs/<abi>/` location used by NDK r22 and older as a fallback.
* The NDK the Flutter tool is building with is now used first, derived from the compiler in the build config.
* Added `sdk.dir` / `ndk.dir` from the project's `local.properties`, `flutter config --android-sdk`, `ndk-bundle` directories and more well known SDK locations to NDK discovery.
* Fixed NDK installations in `PATH` never being detected, because the search directory for `ndk-build` was incorrect.
* Added the `libcpp_shared_path` user define and the `ANDROID_LIBCPP_SHARED_PATH` environment variable to override where the library comes from.
* Failures report each NDK and file checked, and it is looged by the build hook.
* Added `ia32` mapped to `x86`.

## 0.2.0

* Updated `native_toolchain_c` to `0.19.0`.
* Updated `hooks` to `2.0.2`.
* Updated `example` Kotlin version to `2.3.20`, `com.android.application` to `9.0.1` and `gradle` to `9.1.0`.
* Added documentataion about adding `--enable-native-access=ALL-UNNAMED` to `org.gradle.jvmargs` in `gradle.properties`.
* Added `--enable-native-access=ALL-UNNAMED` to `org.gradle.jvmargs` in `example/android/gradle.properties`.

## 0.1.1

* Updated `native_toolchain_c` to `0.18.0`.

## 0.1.0

* Shared Android C++ runtime for Dart / Flutter apps.
