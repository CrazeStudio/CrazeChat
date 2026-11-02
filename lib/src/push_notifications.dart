import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'firebase_options.dart';

// FCM notification payloads carry only opaque routing identifiers. The
// background OS notification never contains decrypted message text.
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
  static String? _registeredToken;
  static String? _registeredUserId;
  static CrazeChatApi? _api;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static final StreamController<String> _chatOpenController =
      StreamController<String>.broadcast();

  static String? _pendingChatId;
  static bool get isAvailable => firebasePushConfigured && defaultFirebaseOptions != null;
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

  static Future<void> _initializeFirebase() async {
    if (_initialized) return;
    if (!firebasePushConfigured || defaultFirebaseOptions == null) return;
    FirebaseMessaging.onBackgroundMessage(crazeChatFirebaseBackgroundHandler);
    await Firebase.initializeApp(options: defaultFirebaseOptions);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final api = _api;
      if (!_enabled || api == null) return;
      try {
        await api.registerPushToken(token);
        _registeredToken = token;
        _registeredUserId = userId;
      } catch (_) {
        // The next app resume or sign-in retries registration.
      }
    });
    _initialized = true;
  }

  static Future<void> configure(
    CrazeChatApi api, {
    required String? userId,
    required bool enabled,
  }) async {
    if (!firebasePushConfigured || defaultFirebaseOptions == null) return;
    _api = api;
    _enabled = enabled;
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
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      if (_registeredUserId == userId && _registeredToken == token) return;
      await api.registerPushToken(token);
      _registeredUserId = userId;
      _registeredToken = token;
    } catch (_) {
      // Push setup is optional; authentication and chat must continue to work.
    }
  }

  static Future<void> unregister(CrazeChatApi api) async {
    final token = _registeredToken;
    try {
      final actualToken = token ?? await FirebaseMessaging.instance.getToken();
      if (actualToken != null && actualToken.isNotEmpty) {
        await api.unregisterPushToken(actualToken);
      }
    } catch (_) {
      // A stale token will be refreshed/replaced on the next successful sign-in.
    } finally {
      _registeredToken = null;
      _registeredUserId = null;
    }
  }
}
