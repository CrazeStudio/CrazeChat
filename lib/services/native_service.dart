import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// Define the C function signatures
typedef NativeGetSecretFunc = ffi.Pointer<Utf8> Function();
typedef DartGetSecretFunc = ffi.Pointer<Utf8> Function();

class NativeKeyLoader {
  static String? _cachedKey;

  /// Loads the shared library and retrieves the decrypted secret key via FFI
  static String getSecretKey() {
    if (_cachedKey != null) {
      return _cachedKey!;
    }

    if (!Platform.isAndroid) {
      return "Mock-Secret-Key-Non-Android";
    }

    try {
      // Open the compiled native shared library (.so)
      final ffi.DynamicLibrary nativeLib =
          ffi.DynamicLibrary.open('libcrazechat-native.so');

      // Look up the clean exported C function
      final DartGetSecretFunc getSecret = nativeLib
          .lookup<ffi.NativeFunction<NativeGetSecretFunc>>('get_secret_key')
          .asFunction<DartGetSecretFunc>();

      // Call the native function and convert the returned C string to Dart
      final ffi.Pointer<Utf8> charPtr = getSecret();
      _cachedKey = charPtr.toDartString();

      return _cachedKey!;
    } catch (e) {
      debugPrint("Failed to load native secret library: $e");
      return "";
    }
  }
}
