import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'firebase_options.dart';

/// A new-message push that arrived while the app was open. It carries only the
/// conversation id; the push payload never contains message text.
class IncomingPush {
  const IncomingPush(this.chatId);
  final String chatId;
}

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
  static String? _registeredFid;
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
  static final StreamController<IncomingPush> _foregroundController =
      StreamController<IncomingPush>.broadcast();
  static final RegExp _chatIdPattern = RegExp(r'^[a-f0-9]{32}$');

  static String? _pendingChatId;
  static String _fidKey(String userId) => 'cc_push_fid_$userId';
  static bool get isAvailable =>
      firebasePushConfigured;
  static Stream<String> get chatOpened => _chatOpenController.stream;

  /// New-message pushes received while the app is in the foreground.
  static Stream<IncomingPush> get foregroundMessages =>
      _foregroundController.stream;

  static String? consumePendingChatId() {
    final value = _pendingChatId;
    _pendingChatId = null;
    return value;
  }

  /// Asks the home screen to open a conversation (used by the in-app banner).
  static void requestOpenChat(String chatId) {
    if (!_chatIdPattern.hasMatch(chatId)) return;
    if (_chatOpenController.hasListener) {
      _chatOpenController.add(chatId);
    } else {
      _pendingChatId = chatId;
    }
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final chatId = message.data['chatId']?.toString();
    if (chatId == null) return;
    requestOpenChat(chatId);
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    if (message.data['type']?.toString() != 'new_message') return;
    final chatId = message.data['chatId']?.toString();
    if (chatId == null || !_chatIdPattern.hasMatch(chatId)) return;
    _foregroundController.add(IncomingPush(chatId));
  }

  static Future<void> _persistFid(String fid) async {
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
      final previousFid = _registeredFid;
      final soundEnabled = _activeSoundEnabled;
      final vibrationEnabled = _activeVibrationEnabled;
      if (previousFid != null && previousFid != fid &&
          _registeredUserId == userId) {
        await registrationApi.unregisterPushFid(previousFid);
      }
      await registrationApi.registerPushFid(
        fid,
        soundEnabled: soundEnabled,
        vibrationEnabled: vibrationEnabled,
      );
      // Sign-out or account switching may have happened while the network
      // request was in flight. Remove the late registration with the captured
      // old session, never with the next account's credentials.
      if (!_enabled || _activeUserId != userId) {
        await registrationApi.unregisterPushFid(fid);
        return;
      }
      await _storage.write(key: _fidKey(userId), value: fid);
      _registeredFid = fid;
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
      // Listen before registering; FCM emits the Firebase Installation ID (FID) asynchronously.
      messaging.onRegistered.listen((fid) {
        unawaited(_persistFid(fid));
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
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
      if (_registeredUserId != userId || _registeredFid == null) {
        _registeredFid = await _storage.read(key: _fidKey(userId));
        _registeredUserId = _registeredFid == null ? null : userId;
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
      if (_registeredUserId == userId && _registeredFid != null) {
        if (_registeredSoundEnabled != soundEnabled ||
            _registeredVibrationEnabled != vibrationEnabled) {
          await api.registerPushFid(
            _registeredFid!,
            soundEnabled: soundEnabled,
            vibrationEnabled: vibrationEnabled,
          );
          _registeredSoundEnabled = soundEnabled;
          _registeredVibrationEnabled = vibrationEnabled;
        }
        return;
      }

      await messaging.register();
    } catch (_) {
      // Push setup is optional; authentication and chat keep working.
    }
  }

  static Future<void> unregister(CrazeChatApi api) async {
    final userId = _activeUserId ?? _registeredUserId;
    String? fid = _registeredFid;
    try {
      fid ??= userId == null
          ? null
          : await _storage.read(key: _fidKey(userId));
    } catch (_) {
      // Do not block sign-out if secure storage is temporarily unavailable.
    }
    _activeUserId = null;
    _enabled = false;
    var removedOnServer = fid == null;
    try {
      if (fid != null) {
        await api.unregisterPushFid(fid);
        removedOnServer = true;
      }
    } catch (_) {
      // Keep the local FID so the same account can retry cleanup next sign-in.
    } finally {
      if (userId != null && removedOnServer) {
        await _storage.delete(key: _fidKey(userId));
      }
      _registeredFid = removedOnServer ? null : fid;
      _registeredUserId = removedOnServer ? null : userId;
      _registeredSoundEnabled = true;
      _registeredVibrationEnabled = true;
    }
  }
}
