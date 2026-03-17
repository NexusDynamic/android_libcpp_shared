import 'dart:ffi' as ffi;

final class _AndroidLibcppShared {
  static final instance = _AndroidLibcppShared._();
  final ffi.DynamicLibrary lib;
  _AndroidLibcppShared._() : lib = ffi.DynamicLibrary.open('libc++_shared.so');
}

ffi.DynamicLibrary get libCppShared => _AndroidLibcppShared.instance.lib;
