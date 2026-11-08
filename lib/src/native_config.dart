import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

/// Reads the API origin and the shared access key from the native library
/// `libcrazecfg.so`, where they are stored XOR-masked instead of as plain
/// strings in the Dart snapshot. This raises the effort needed to lift the key
/// out of the APK; it does not make the key secret, because the app has to
/// decode it to use it. Real protection comes from per-user authentication.
///
/// Falls back to the `--dart-define` values when the library is absent
/// (host tests, desktop, or builds without the native config step).
class NativeConfig {
  const NativeConfig._();

  static const _fallbackUrl = String.fromEnvironment('BURL');
  static const _fallbackKey = String.fromEnvironment('KEY');
  static bool _loaded = false;
  static String _nativeUrl = '';
  static String _nativeKey = '';

  static void _load() {
    if (_loaded) return;
    _loaded = true;
    if (!Platform.isAndroid) return;
    try {
      final library = DynamicLibrary.open('libcrazecfg.so');
      final readUrl = library
          .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
            'cc_url',
          );
      final readKey = library
          .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
            'cc_key',
          );
      _nativeUrl = _readCString(readUrl());
      _nativeKey = _readCString(readKey());
    } catch (_) {
      // Library missing: the dart-define fallback below is used instead.
    }
  }

  static String _readCString(Pointer<Uint8> pointer) {
    final bytes = <int>[];
    for (var i = 0; i < 4096; i++) {
      final byte = pointer[i];
      if (byte == 0) break;
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String get url {
    _load();
    return _nativeUrl.isNotEmpty ? _nativeUrl : _fallbackUrl;
  }

  static String get key {
    _load();
    return _nativeKey.isNotEmpty ? _nativeKey : _fallbackKey;
  }
}
