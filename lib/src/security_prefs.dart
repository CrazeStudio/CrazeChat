import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-level privacy switches that are applied by the Android host.
class SecurityPrefs {
  const SecurityPrefs._();

  static const _storage = FlutterSecureStorage();
  static const _channel = MethodChannel('com.crazestudio.crazechat/security');
  static const _screenSecureKey = 'pref_screen_secure';

  /// Screenshots, screen recording and the recent-apps preview are blocked
  /// unless the user turns this off.
  static Future<bool> screenSecureEnabled() async {
    try {
      return await _storage.read(key: _screenSecureKey) != 'false';
    } catch (_) {
      return true;
    }
  }

  static Future<void> setScreenSecure(bool enabled) async {
    try {
      await _storage.write(key: _screenSecureKey, value: enabled.toString());
    } catch (_) {
      // The window flag below still applies for this session.
    }
    await applyScreenSecure(enabled);
  }

  static Future<void> applyStoredScreenSecure() async =>
      applyScreenSecure(await screenSecureEnabled());

  static Future<void> applyScreenSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      // Not running inside the Android host (tests, desktop).
    } catch (_) {
      // Leave the native default (blocked) in place.
    }
  }
}
