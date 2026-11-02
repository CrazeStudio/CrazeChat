import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'firebase_options.dart';

// FCM notifications are generic. The background OS notification never carries
// decrypted text, reply quotes or reaction payloads.
@pragma('vm:entry-point')
Future<void> crazeChatFirebaseBackgroundHandler(RemoteMessage message) async {
  if (!firebasePushConfigured || defaultFirebaseOptions == null) return;
  try {
    await Firebase.initializeApp(options: defaultFirebaseOptions);
  } catch (_) {
    // Firebase may already be initialized in this background isolate.
  }
}

class PushNotificationService {
  PushNotificationService._();

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

  static String? _pendingChatId;
  static bool get isAvailable =>
      firebasePushConfigured && defaultFirebaseOptions != null;
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

  static Future<void> _persistFid(String fid) async {
    final api = _api;
    final userId = _activeUserId;
    if (!_enabled || api == null || userId == null || api.token == null) return;
    try {
      await api.registerPushFid(
        fid,
        soundEnabled: _activeSoundEnabled,
        vibrationEnabled: _activeVibrationEnabled,
      );
      _registeredFid = fid;
      _registeredUserId = userId;
      _registeredSoundEnabled = _activeSoundEnabled;
      _registeredVibrationEnabled = _activeVibrationEnabled;
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
      // Listen before calling register(); FCM emits the installation ID
      // asynchronously through onRegistered.
      messaging.onRegistered.listen((fid) {
        unawaited(_persistFid(fid));
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
    final fid = _registeredFid;
    _activeUserId = null;
    _enabled = false;
    try {
      if (fid != null) {
        await api.unregisterPushFid(fid);
      }
    } catch (_) {
      // A stale association is harmless: notifications contain no message text.
    } finally {
      _registeredFid = null;
      _registeredUserId = null;
      _registeredSoundEnabled = true;
      _registeredVibrationEnabled = true;
    }
  }
}
