import 'package:audioplayers/audioplayers.dart';

/// Low-latency, bundled sounds for the foreground chat experience.
///
/// Android notification-channel sounds remain managed by FCM/the OS; this
/// service is only for sounds while CrazeChat is open.
class CrazeChatSoundEffects {
  CrazeChatSoundEffects._();

  static Future<AudioPool>? _incomingPool;
  static Future<AudioPool>? _outgoingPool;

  static Future<void> initialize() async {
    await Future.wait([_warmPool(incoming: true), _warmPool(incoming: false)]);
  }

  static Future<void> playIncoming({required bool enabled}) =>
      _play(incoming: true, enabled: enabled);

  static Future<void> playOutgoing({required bool enabled}) =>
      _play(incoming: false, enabled: enabled);

  static Future<void> _warmPool({required bool incoming}) async {
    try {
      await _poolFor(incoming: incoming);
    } catch (_) {
      _forgetPool(incoming: incoming);
    }
  }

  static Future<void> _play({
    required bool incoming,
    required bool enabled,
  }) async {
    if (!enabled) {
      return;
    }
    try {
      final pool = await _poolFor(incoming: incoming);
      await pool.start(volume: incoming ? 0.48 : 0.36);
    } catch (_) {
      // Audio is optional. A plugin/device playback failure must not disrupt chat.
      _forgetPool(incoming: incoming);
    }
  }

  static Future<AudioPool> _poolFor({required bool incoming}) {
    final existing = incoming ? _incomingPool : _outgoingPool;
    if (existing != null) {
      return existing;
    }

    final created = AudioPool.createFromAsset(
      path: incoming ? 'sounds/incoming.wav' : 'sounds/send.wav',
      minPlayers: 1,
      maxPlayers: 2,
      playerMode: PlayerMode.lowLatency,
    );
    if (incoming) {
      _incomingPool = created;
    } else {
      _outgoingPool = created;
    }
    return created;
  }

  static void _forgetPool({required bool incoming}) {
    if (incoming) {
      _incomingPool = null;
    } else {
      _outgoingPool = null;
    }
  }

  static Future<void> dispose() async {
    final pools = [_incomingPool, _outgoingPool];
    _incomingPool = null;
    _outgoingPool = null;
    await Future.wait(pools.map(_disposePool));
  }

  static Future<void> _disposePool(Future<AudioPool>? pending) async {
    if (pending == null) {
      return;
    }
    try {
      await (await pending).dispose();
    } catch (_) {
      // The pool may not have finished initializing or may already be closed.
    }
  }
}
