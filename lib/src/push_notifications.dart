import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'firebase_options.dart';

// FCM notifications are generic. The background OS notification never carries
// decrypted text, reply quotes or reaction payloads.
@pragma('vm:entry-point')
Future<void> crazeChatFirebaseBackgroundHandler(RemoteMessage message) async {
  if (!firebasePushConfigured) return;
  try {
    await Firebase.initializeApp(options: defaultFirebaseOptions);
  } catch (_) {
    // Firebase may already be initialized in this background isolate.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static bool _initialized = false;
  static bool _enabled = true;
  static String? _registeredToken;
  static String? _registeredUserId;
  static String? _activeUserId;
  static bool _registeredSoundEnabled = true;
  static bool _registeredVibrationEnabled = true;
  static bool _activeSoundEnabled = true;
  static bool _activeVibrationEnabled = true;
  static CrazeChatApi? _api;
  static Future<void>? _initializing;
  static final StreamController<String> _chatOpenController =
      StreamController<String>.broadcast();

  static String? _pendingChatId;
  static String _tokenKey(String userId) => 'cc_push_token_$userId';
  static bool get isAvailable =>
      firebasePushConfigured;
  static Stream<String> get chatOpened => _chatOpenController.stream;

  static String? consumePendingChatId() {
    final value = _pendingChatId;
    _pendingChatId = null;
    return value;
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final chatId = message.data['chatId']?.toString();
    if (chatId == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(chatId)) return;
    if (_chatOpenController.hasListener) {
      _chatOpenController.add(chatId);
    } else {
      _pendingChatId = chatId;
    }
  }

  static Future<void> _persistToken(String token) async {
    final api = _api;
    final userId = _activeUserId;
    final sessionToken = api?.token;
    if (!_enabled || api == null || userId == null ||
        sessionToken == null || sessionToken.isEmpty) {
      return;
    }
    // Capture the JWT at registration start. ChatSession reuses its API
    // object when switching accounts, so a pending operation must not adopt
    // the next account's Authorization header midway through the request.
    final registrationApi = CrazeChatApi(token: sessionToken);
    try {
      final previousToken = _registeredToken;
      final soundEnabled = _activeSoundEnabled;
      final vibrationEnabled = _activeVibrationEnabled;
      if (previousToken != null && previousToken != token &&
          _registeredUserId == userId) {
        await registrationApi.unregisterPushToken(previousToken);
      }
      await registrationApi.registerPushToken(
        token,
        soundEnabled: soundEnabled,
        vibrationEnabled: vibrationEnabled,
      );
      // Sign-out or account switching may have happened while the network
      // request was in flight. Remove the late registration with the captured
      // old session, never with the next account's credentials.
      if (!_enabled || _activeUserId != userId) {
        await registrationApi.unregisterPushToken(token);
        return;
      }
      await _storage.write(key: _tokenKey(userId), value: token);
      _registeredToken = token;
      _registeredUserId = userId;
      _registeredSoundEnabled = soundEnabled;
      _registeredVibrationEnabled = vibrationEnabled;
    } catch (_) {
      // Re-run configure/register on the next app resume or session change.
    }
  }

  static Future<void> _initializeFirebase() async {
    if (_initialized) return;
    if (_initializing != null) return _initializing;
    if (!isAvailable) return;
    _initializing = () async {
      FirebaseMessaging.onBackgroundMessage(crazeChatFirebaseBackgroundHandler);
      await Firebase.initializeApp(options: defaultFirebaseOptions);
      final messaging = FirebaseMessaging.instance;
      // Listen for token rotation so the backend always has a current send target.
      messaging.onTokenRefresh.listen((token) {
        unawaited(_persistToken(token));
      }, onError: (Object error) {
        // Retry token refresh registration on the next configure/resume.
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleNotificationTap(initial);
      _initialized = true;
    }();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  static Future<void> configure(
    CrazeChatApi api, {
    required String? userId,
    required bool enabled,
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {
    if (!isAvailable) return;
    _api = api;
    _activeUserId = userId;
    _enabled = enabled;
    _activeSoundEnabled = soundEnabled;
    _activeVibrationEnabled = vibrationEnabled;
    try {
      await _initializeFirebase();
      if (!_initialized) return;
      final messaging = FirebaseMessaging.instance;
      if (!enabled || userId == null || api.token == null) {
        await unregister(api);
        await messaging.setAutoInitEnabled(false);
        return;
      }

      // Restore the device association after process death so sign-out and
      // preference updates can still remove/update the correct account link.
      if (_registeredUserId != userId || _registeredToken == null) {
        _registeredToken = await _storage.read(key: _tokenKey(userId));
        _registeredUserId = _registeredToken == null ? null : userId;
      }

      await messaging.setAutoInitEnabled(true);
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final permitted =
          permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional;
      if (!permitted) {
        await unregister(api);
        await messaging.setAutoInitEnabled(false);
        return;
      }
      if (_registeredUserId == userId && _registeredToken != null) {
        if (_registeredSoundEnabled != soundEnabled ||
            _registeredVibrationEnabled != vibrationEnabled) {
          await api.registerPushToken(
            _registeredToken!,
            soundEnabled: soundEnabled,
            vibrationEnabled: vibrationEnabled,
          );
          _registeredSoundEnabled = soundEnabled;
          _registeredVibrationEnabled = vibrationEnabled;
        }
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        throw StateError('Firebase did not provide an FCM registration token.');
      }
      await _persistToken(token);
    } catch (_) {
      // Push setup is optional; authentication and chat keep working.
    }
  }

  static Future<void> unregister(CrazeChatApi api) async {
    final userId = _activeUserId ?? _registeredUserId;
    String? token = _registeredToken;
    try {
      token ??= userId == null
          ? null
          : await _storage.read(key: _tokenKey(userId));
    } catch (_) {
      // Do not block sign-out if secure storage is temporarily unavailable.
    }
    _activeUserId = null;
    _enabled = false;
    var removedOnServer = token == null;
    try {
      if (token != null) {
        await api.unregisterPushToken(token);
        removedOnServer = true;
      }
    } catch (_) {
      // Keep the local FID so the same account can retry cleanup next sign-in.
    } finally {
      if (userId != null && removedOnServer) {
        await _storage.delete(key: _tokenKey(userId));
      }
      _registeredToken = removedOnServer ? null : token;
      _registeredUserId = removedOnServer ? null : userId;
      _registeredSoundEnabled = true;
      _registeredVibrationEnabled = true;
    }
  }
}
