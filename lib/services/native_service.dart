import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef NativeGetSecretFunc = ffi.Pointer<Utf8> Function();
typedef DartGetSecretFunc = ffi.Pointer<Utf8> Function();

class NativeKeyLoader {
  static String? _cachedKey1;
  static String? _cachedKey2;

  static ffi.DynamicLibrary? _nativeLib;

  static ffi.DynamicLibrary _getLibrary() {
    if (_nativeLib != null) return _nativeLib!;
    _nativeLib = ffi.DynamicLibrary.open('libcrazechat-native.so');
    return _nativeLib!;
  }

  /// Retrieves Secret Key 1 (e.g., Main API Key) without overwriting Key 2
  static String getSecretKey1() {
    if (_cachedKey1 != null) return _cachedKey1!;
    if (!Platform.isAndroid) return "Mock-Key-1";

    try {
      final lib = _getLibrary();
      final getSecret = lib
          .lookup<ffi.NativeFunction<NativeGetSecretFunc>>('get_secret_key_1')
          .asFunction<DartGetSecretFunc>();

      _cachedKey1 = getSecret().toDartString();
      return _cachedKey1!;
    } catch (e) {
      debugPrint("Error loading Secret Key 1: $e");
      return "";
    }
  }

  /// Retrieves Secret Key 2 (e.g., Secondary Token / Salt) into an isolated cache
  static String getSecretKey2() {
    if (_cachedKey2 != null) return _cachedKey2!;
    if (!Platform.isAndroid) return "Mock-Key-2";

    try {
      final lib = _getLibrary();
      final getSecret = lib
          .lookup<ffi.NativeFunction<NativeGetSecretFunc>>('get_secret_key_2')
          .asFunction<DartGetSecretFunc>();

      _cachedKey2 = getSecret().toDartString();
      return _cachedKey2!;
    } catch (e) {
      debugPrint("Error loading Secret Key 2: $e");
      return "";
    }
  }
}
