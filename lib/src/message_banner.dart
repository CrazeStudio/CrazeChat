import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'active_chat.dart';
import 'profile_photo.dart';
import 'push_notifications.dart';
import 'session.dart';
import 'sound_effects.dart';

class _BannerData {
  const _BannerData({
    required this.chatId,
    required this.name,
    required this.userId,
    required this.photoUrl,
    required this.count,
  });

  final String chatId;
  final String name;
  final String? userId;
  final String? photoUrl;
  final int count;

  _BannerData more() => _BannerData(
    chatId: chatId,
    name: name,
    userId: userId,
    photoUrl: photoUrl,
    count: count + 1,
  );
}

/// Shows a banner at the top of the screen when a message arrives for a chat
/// that is not currently open. It sits above the whole app, so it appears on
/// every screen. The text of the message is never shown: push notifications
/// carry no plaintext, and the banner only says that something new arrived.
class MessageBannerRoot extends StatefulWidget {
  const MessageBannerRoot({super.key, required this.child});
  final Widget child;

  @override
  State<MessageBannerRoot> createState() => _MessageBannerRootState();
}

class _MessageBannerRootState extends State<MessageBannerRoot> {
  StreamSubscription<IncomingPush>? _subscription;
  Timer? _hideTimer;
  _BannerData? _banner;
  int _serial = 0;
  final Map<String, Map<String, dynamic>> _peers = {};

  @override
  void initState() {
    super.initState();
    _subscription = PushNotificationService.foregroundMessages.listen(
      (push) => unawaited(_onPush(push)),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPeers(ChatSession session) async {
    try {
      final data = await session.api.listChats();
      final me = session.userId;
      for (final raw in (data['chats'] as List? ?? const []).whereType<Map>()) {
        final chat = Map<String, dynamic>.from(raw);
        final id = chat['id']?.toString();
        if (id == null) continue;
        for (final member in (chat['members'] as List? ?? const [])
            .whereType<Map>()) {
          if (member['id']?.toString() != me) {
            _peers[id] = Map<String, dynamic>.from(member);
            break;
          }
        }
      }
    } catch (_) {
      // Without the chat list the banner falls back to a generic title.
    }
  }

  Future<void> _onPush(IncomingPush push) async {
    final session = ChatSession.current;
    if (session == null || !session.signedIn || !session.unlocked) return;
    if (ActiveChat.isOpen(push.chatId)) return;
    if (!_peers.containsKey(push.chatId)) await _loadPeers(session);
    if (!mounted || ActiveChat.isOpen(push.chatId)) return;
    final peer = _peers[push.chatId];
    final existing = _banner;
    setState(() {
      _banner = existing != null && existing.chatId == push.chatId
          ? existing.more()
          : _BannerData(
              chatId: push.chatId,
              name: peer?['username']?.toString() ?? 'New message',
              userId: peer?['id']?.toString(),
              photoUrl: peer?['photoUrl']?.toString(),
              count: 1,
            );
      _serial++;
    });
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), _dismiss);
    unawaited(
      CrazeChatSoundEffects.playIncoming(enabled: session.soundEffectsEnabled),
    );
    if (session.vibrationEnabled) HapticFeedback.lightImpact();
  }

  void _dismiss() {
    _hideTimer?.cancel();
    if (mounted && _banner != null) setState(() => _banner = null);
  }

  void _open(_BannerData banner) {
    _dismiss();
    PushNotificationService.requestOpenChat(banner.chatId);
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final mode = ChatSession.current?.themeMode ?? ThemeMode.system;
    final dark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            view.platformDispatcher.platformBrightness == Brightness.dark);
    final banner = _banner;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery.fromView(
        view: view,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -1.2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: banner == null
                        ? const SizedBox.shrink(key: ValueKey('no-banner'))
                        : _BannerCard(
                            key: ValueKey(_serial),
                            banner: banner,
                            dark: dark,
                            onOpen: () => _open(banner),
                            onDismiss: _dismiss,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    super.key,
    required this.banner,
    required this.dark,
    required this.onOpen,
    required this.onDismiss,
  });

  final _BannerData banner;
  final bool dark;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final surface = dark ? const Color(0xFF20312D) : Colors.white;
    final border = dark ? const Color(0xFF3F5A51) : const Color(0xFFD5E2DC);
    final text = dark ? const Color(0xFFF1F7F4) : const Color(0xFF142A27);
    final muted = dark ? const Color(0xFFB5C6BF) : const Color(0xFF55706A);
    return Dismissible(
      key: ValueKey('banner-${banner.chatId}'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismiss(),
      child: Semantics(
        button: true,
        label: 'New message from ${banner.name}. Double tap to open.',
        child: Material(
          color: surface,
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  _BannerAvatar(
                    name: banner.name,
                    userId: banner.userId,
                    photoUrl: banner.photoUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          banner.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          banner.count > 1
                              ? '${banner.count} new messages'
                              : 'New encrypted message',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: muted, size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerAvatar extends StatefulWidget {
  const _BannerAvatar({required this.name, this.userId, this.photoUrl});
  final String name;
  final String? userId;
  final String? photoUrl;

  @override
  State<_BannerAvatar> createState() => _BannerAvatarState();
}

class _BannerAvatarState extends State<_BannerAvatar> {
  late final Future<Uint8List?> _photo;

  @override
  void initState() {
    super.initState();
    final id = widget.userId;
    final url = widget.photoUrl;
    _photo = id == null || url == null || url.isEmpty
        ? Future<Uint8List?>.value(null)
        : ProfilePhotoCache.load(userId: id, url: url);
  }

  @override
  Widget build(BuildContext context) {
    const palette = [
      Color(0xFF176B5B),
      Color(0xFF315D9B),
      Color(0xFF8A4F83),
      Color(0xFF9A6238),
      Color(0xFF536B36),
      Color(0xFF6A5AA6),
    ];
    final normalized = widget.name.trim();
    final hash = normalized.codeUnits.fold<int>(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    final initial = normalized.isEmpty
        ? '?'
        : normalized.substring(0, 1).toUpperCase();
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) => CircleAvatar(
        radius: 22,
        backgroundColor: palette[hash % palette.length],
        foregroundImage: snapshot.data == null
            ? null
            : MemoryImage(snapshot.data!),
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
