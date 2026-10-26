import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'core.dart';

const _brandBlue = Color(0xFF2563EB);
const _muted = Color(0xFF64748B);
const _lightCanvas = Color(0xFFF8FAFC);
const _lightBorder = Color(0xFFE2E8F0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CrazeChatApp(api: ApiClient(), crypto: CryptoService()));
}

ThemeData _makeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _brandBlue,
    brightness: brightness,
    surface: dark ? const Color(0xFF1E293B) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F172A) : _lightCanvas,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0F172A) : _lightCanvas,
      foregroundColor: dark ? Colors.white : const Color(0xFF0F172A),
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1E293B) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: dark ? Colors.white12 : _lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _brandBlue, width: 1.4),
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF172337) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: dark ? Colors.white10 : _lightBorder),
      ),
    ),
    dividerTheme: DividerThemeData(color: dark ? Colors.white12 : _lightBorder, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(56, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
  );
}

class CrazeChatApp extends StatefulWidget {
  const CrazeChatApp({super.key, required this.api, required this.crypto});
  final ApiClient api;
  final CryptoService crypto;

  @override
  State<CrazeChatApp> createState() => _CrazeChatAppState();
}

class _CrazeChatAppState extends State<CrazeChatApp> {
  String? _uid;
  String _username = '';
  ThemeMode _themeMode = ThemeMode.system;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _restoreApp();
  }

  Future<void> _restoreApp() async {
    try {
      final storedTheme = await widget.api.themeMode;
      final session = await widget.api.readSession();
      if (session != null && session['uid'] != null) {
        final hasLocalIdentity = await widget.crypto.hasIdentity(session['uid']!);
        if (hasLocalIdentity) {
          _uid = session['uid'];
          _username = session['username'] ?? '';
          unawaited(widget.api.setPresence(true).catchError((_) => <String, dynamic>{}));
        } else {
          // Require a password again so the encrypted cloud backup can be restored safely.
          await widget.api.clearSession();
        }
      }
      _themeMode = switch (storedTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // A local storage problem should return the user to sign-in, not crash the app.
      _uid = null;
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.api.setThemeMode(switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }

  Future<void> _signedIn(String uid, String username, String password) async {
    await widget.crypto.ensureIdentity(uid: uid, username: username, password: password, api: widget.api);
    await widget.api.setPresence(true);
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _username = username;
    });
  }

  Future<void> _signedOut() async {
    final uid = _uid;
    if (uid != null) {
      try {
        await widget.api.setPresence(false);
      } catch (_) {}
    }
    try {
      await widget.api.logout();
    } catch (_) {
      await widget.api.clearSession();
    }
    if (mounted) setState(() {
      _uid = null;
      _username = '';
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CrazeChat',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: _makeTheme(Brightness.light),
        darkTheme: _makeTheme(Brightness.dark),
        home: _booting
            ? const _SplashScreen()
            : _uid == null
                ? _AuthScreen(api: widget.api, onAuthenticated: _signedIn)
                : _AppShell(
                    api: widget.api,
                    crypto: widget.crypto,
                    uid: _uid!,
                    username: _username,
                    themeMode: _themeMode,
                    onThemeChanged: _setTheme,
                    onSignOut: _signedOut,
                  ),
      );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _BrandMark(size: 72),
            SizedBox(height: 18),
            Text('CrazeChat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
            SizedBox(height: 20),
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ]),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 42});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _brandBlue,
          borderRadius: BorderRadius.circular(size * .30),
          boxShadow: const [BoxShadow(color: Color(0x222563EB), blurRadius: 18, offset: Offset(0, 7))],
        ),
        child: Icon(Icons.forum_rounded, color: Colors.white, size: size * .52),
      );
}

class _AuthScreen extends StatefulWidget {
  const _AuthScreen({required this.api, required this.onAuthenticated});
  final ApiClient api;
  final Future<void> Function(String uid, String username, String password) onAuthenticated;

  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _registering = true;
  bool _hidePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(username)) {
      setState(() => _error = 'Username must be 3–24 characters using letters, numbers, or underscores.');
      return;
    }
    if (_registering && password.length < 10) {
      setState(() => _error = 'Use a password with at least 10 characters.');
      return;
    }
    if (password.isEmpty || password.length > 128) {
      setState(() => _error = 'Enter a valid password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await widget.api.register(username, password);
      } else {
        await widget.api.login(username, password);
      }
      final session = await widget.api.readSession();
      if (session == null) throw const ApiException(502, 'The server did not create a valid session.');
      await widget.onAuthenticated(session['uid']!, session['username']!, password);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: _BrandMark(size: 78)),
                  const SizedBox(height: 26),
                  const Text('CrazeChat', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
                  const SizedBox(height: 8),
                  Text(
                    _registering ? 'A calmer space for your conversations.' : 'Welcome back. Your conversations are waiting.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 30),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(_registering ? 'Create your account' : 'Sign in',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline_rounded)),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            obscureText: _hidePassword,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _hidePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              ),
                            ),
                          ),
                          if (_registering) ...[
                            const SizedBox(height: 9),
                            const Text('3–24 character username · 10+ character password',
                                style: TextStyle(color: _muted, fontSize: 12)),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer.withOpacity(.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_registering ? 'Create account' : 'Log in', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 5),
                          TextButton(
                            onPressed: _busy ? null : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                            child: Text(_registering ? 'Already have an account? Log in' : 'New to CrazeChat? Create account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_outline_rounded, size: 15, color: dark ? Colors.white54 : _muted),
                    const SizedBox(width: 7),
                    const Flexible(child: Text('Private keys stay on your device.', style: TextStyle(color: _muted, fontSize: 12))),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.api,
    required this.crypto,
    required this.uid,
    required this.username,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onSignOut,
  });
  final ApiClient api;
  final CryptoService crypto;
  final String uid;
  final String username;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final Future<void> Function() onSignOut;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _index = 0;

  Future<void> _openChat(String chatId, String fallbackTitle) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ChatScreen(
        api: widget.api,
        crypto: widget.crypto,
        uid: widget.uid,
        username: widget.username,
        chatId: chatId,
        fallbackTitle: fallbackTitle,
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _ChatsTab(api: widget.api, crypto: widget.crypto, uid: widget.uid, username: widget.username, onOpenChat: _openChat),
          _PeopleTab(api: widget.api, crypto: widget.crypto, uid: widget.uid, username: widget.username, onOpenChat: _openChat),
          _SettingsTab(
            api: widget.api,
            crypto: widget.crypto,
            uid: widget.uid,
            username: widget.username,
            themeMode: widget.themeMode,
            onThemeChanged: widget.onThemeChanged,
            onSignOut: widget.onSignOut,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_rounded), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'People'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class _ChatSummary {
  const _ChatSummary({required this.chat, required this.title, required this.preview, required this.previewAt});
  final ChatRecord chat;
  final String title;
  final String preview;
  final DateTime previewAt;
}

class _ChatsTab extends StatefulWidget {
  const _ChatsTab({required this.api, required this.crypto, required this.uid, required this.username, required this.onOpenChat});
  final ApiClient api;
  final CryptoService crypto;
  final String uid;
  final String username;
  final Future<void> Function(String chatId, String title) onOpenChat;

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  final _search = TextEditingController();
  Timer? _timer;
  List<_ChatSummary> _chats = [];
  bool _loading = true;
  String? _error;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<String> _messagePreview(ChatMessage message, ChatRecord chat) async {
    if (message.nonce.isEmpty) return message.ciphertext.isEmpty ? 'Message' : message.ciphertext;
    try {
      if (chat.isGroup) {
        if (widget.crypto.groupMessageVersion(message.ciphertext) > 0) {
          return await widget.crypto.decryptGroup(
            uid: widget.uid,
            api: widget.api,
            chatId: chat.id,
            ciphertext: message.ciphertext,
            nonce: message.nonce,
          );
        }
        return await widget.crypto.decryptLegacyGroup(chat.id, message.ciphertext, message.nonce);
      }
      final peerId = chat.memberIds.firstWhere((id) => id != widget.uid, orElse: () => '');
      if (peerId.isEmpty) return 'Encrypted message';
      final profile = asJsonMap((await widget.api.getUser(peerId))['user']);
      final publicKey = stringValue(profile['publicKey']);
      if (publicKey.isEmpty) return 'Encrypted message';
      return await widget.crypto.decryptDirect(widget.uid, publicKey, message.ciphertext, message.nonce);
    } catch (_) {
      return 'Encrypted message';
    }
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!quiet && mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = (await widget.api.getChats()).map(ChatRecord.fromJson).toList();
      final summaries = <_ChatSummary>[];
      for (final chat in records.take(30)) {
        var title = chat.title;
        if (!chat.isGroup || title.isEmpty) {
          final peer = chat.memberIds.firstWhere((id) => id != widget.uid, orElse: () => '');
          if (peer.isNotEmpty) {
            try {
              final data = asJsonMap((await widget.api.getUser(peer))['user']);
              final name = stringValue(data['username']);
              if (name.isNotEmpty) title = chat.isGroup ? (title.isEmpty ? 'Group chat' : title) : name;
            } catch (_) {}
          }
        }
        if (title.isEmpty) title = chat.isGroup ? 'Group chat' : 'Conversation';
        String preview = 'Tap to open conversation';
        var date = chat.createdAt;
        try {
          final messages = await widget.api.getMessages(chat.id, limit: 1);
          if (messages.isNotEmpty) {
            final last = ChatMessage.fromJson(messages.last);
            preview = await _messagePreview(last, chat);
            date = last.createdAt;
          }
        } catch (_) {}
        summaries.add(_ChatSummary(chat: chat, title: title, preview: preview, previewAt: date));
      }
      summaries.sort((a, b) => b.previewAt.compareTo(a.previewAt));
      if (mounted) setState(() {
        _chats = summaries;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        if (!quiet || _chats.isEmpty) _error = error.toString();
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _newChat() async {
    final result = await showDialog<_CreateChatResult>(
      context: context,
      builder: (_) => const _CreateChatDialog(),
    );
    if (result == null || !mounted) return;
    try {
      if (!result.isGroup) {
        final target = await _resolveUser(widget.api, result.memberText.trim());
        if (target.userId == widget.uid) throw const ApiException(400, 'You cannot start a chat with yourself.');
        final created = asJsonMap((await widget.api.createChat(
          memberIds: [target.userId],
          title: target.username,
          isGroup: false,
        ))['chat']);
        await widget.onOpenChat(stringValue(created['id']), target.username);
      } else {
        final names = result.memberText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        if (names.isEmpty) throw const ApiException(400, 'Add at least one member username or user ID.');
        final members = <String>[];
        for (final name in names) {
          final profile = await _resolveUser(widget.api, name);
          if (profile.userId != widget.uid) members.add(profile.userId);
        }
        final created = asJsonMap((await widget.api.createChat(
          memberIds: members,
          title: result.title.trim(),
          isGroup: true,
        ))['chat']);
        final id = stringValue(created['id']);
        try {
          final chat = ChatRecord.fromJson(asJsonMap((await widget.api.getChat(id))['chat']));
          await widget.crypto.rotateGroupKey(uid: widget.uid, username: widget.username, api: widget.api, chat: chat);
        } catch (error) {
          _showSnack(context, 'Group created, but key setup needs attention: $error');
        }
        await widget.onOpenChat(id, result.title.trim().isEmpty ? 'Group chat' : result.title.trim());
      }
      await _refresh();
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase().trim();
    final visible = _chats.where((item) => item.title.toLowerCase().contains(query) || item.preview.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const _BrandMark(size: 36),
          const SizedBox(width: 10),
          const Text('CrazeChat', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.7)),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh conversations', onPressed: () => _refresh(), icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'New chat', onPressed: _newChat, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('New chat'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Search conversations', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 3, 20, 13),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('YOUR MESSAGES', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
          ),
        ),
        Expanded(
          child: _loading && _chats.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _chats.isEmpty
                  ? _EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load conversations', detail: _error!, action: TextButton(onPressed: () => _refresh(), child: const Text('Try again')))
                  : visible.isEmpty
                      ? _EmptyState(icon: Icons.chat_bubble_outline_rounded, title: query.isEmpty ? 'No conversations yet' : 'No matching conversations', detail: query.isEmpty ? 'Start a direct chat or create a group with a CrazeChat user.' : 'Try another name or message.')
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                                leading: _Avatar(label: item.title, group: item.chat.isGroup),
                                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text(item.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted)),
                                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text(_friendlyTime(item.previewAt), style: const TextStyle(color: _muted, fontSize: 11)),
                                  const SizedBox(height: 5),
                                  const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
                                ]),
                                onTap: () => widget.onOpenChat(item.chat.id, item.title),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

class _CreateChatResult {
  const _CreateChatResult({required this.isGroup, required this.memberText, this.title = ''});
  final bool isGroup;
  final String memberText;
  final String title;
}

class _CreateChatDialog extends StatefulWidget {
  const _CreateChatDialog();

  @override
  State<_CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<_CreateChatDialog> {
  final _name = TextEditingController();
  final _members = TextEditingController();
  bool _group = false;

  @override
  void dispose() {
    _name.dispose();
    _members.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New conversation'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Direct'), icon: Icon(Icons.person_outline_rounded)),
                ButtonSegment(value: true, label: Text('Group'), icon: Icon(Icons.groups_outlined)),
              ],
              selected: {_group},
              onSelectionChanged: (value) => setState(() => _group = value.first),
            ),
            if (_group) ...[
              const SizedBox(height: 14),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Group name')),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _members,
              autofocus: true,
              minLines: _group ? 2 : 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _group ? 'Member usernames or IDs' : 'Username or user ID',
                hintText: _group ? 'alex, sam_01' : 'Enter a username or ID',
                helperText: _group ? 'Separate multiple members with commas.' : 'We will look up the account on the server.',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_members.text.trim().isEmpty) return;
              Navigator.pop(context, _CreateChatResult(isGroup: _group, memberText: _members.text, title: _name.text));
            },
            child: const Text('Continue'),
          ),
        ],
      );
}

class _PeopleTab extends StatefulWidget {
  const _PeopleTab({required this.api, required this.crypto, required this.uid, required this.username, required this.onOpenChat});
  final ApiClient api;
  final CryptoService crypto;
  final String uid;
  final String username;
  final Future<void> Function(String chatId, String title) onOpenChat;

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  final _search = TextEditingController();
  List<UserProfile> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = (await widget.api.getUsers())
          .map(UserProfile.fromJson)
          .where((user) => user.userId != widget.uid)
          .toList()
        ..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
      if (mounted) setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _start(UserProfile user) async {
    try {
      final result = asJsonMap((await widget.api.createChat(
        memberIds: [user.userId],
        title: user.username,
        isGroup: false,
      ))['chat']);
      await widget.onOpenChat(stringValue(result['id']), user.username);
      await _load();
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = _users.where((user) =>
      user.username.toLowerCase().contains(query) || user.userId.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('People', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.5)),
        actions: [IconButton(tooltip: 'Refresh people', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<_CreateChatResult>(context: context, builder: (_) => const _CreateChatDialog()).then((result) async {
          if (result == null) return;
          try {
            if (!result.isGroup) {
              final user = await _resolveUser(widget.api, result.memberText.trim());
              await _start(user);
              return;
            }
            final names = result.memberText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
            final ids = <String>[];
            for (final name in names) {
              final user = await _resolveUser(widget.api, name);
              if (user.userId != widget.uid) ids.add(user.userId);
            }
            final created = asJsonMap((await widget.api.createChat(memberIds: ids, title: result.title.trim(), isGroup: true))['chat']);
            final chatId = stringValue(created['id']);
            final chat = ChatRecord.fromJson(asJsonMap((await widget.api.getChat(chatId))['chat']));
            await widget.crypto.rotateGroupKey(uid: widget.uid, username: widget.username, api: widget.api, chat: chat);
            await widget.onOpenChat(chatId, result.title.trim().isEmpty ? 'Group chat' : result.title.trim());
          } catch (error) {
            if (mounted) _showSnack(context, error.toString());
          }
        }),
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('New group'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Find people by username or ID', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        Expanded(
          child: _loading && _users.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _users.isEmpty
                  ? _EmptyState(icon: Icons.cloud_off_outlined, title: 'People are unavailable', detail: _error!, action: TextButton(onPressed: _load, child: const Text('Retry')))
                  : filtered.isEmpty
                      ? const _EmptyState(icon: Icons.person_search_rounded, title: 'No users found', detail: 'People appear here when their profiles allow discovery.')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 74),
                            itemBuilder: (context, index) {
                              final user = filtered[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                leading: _Avatar(label: user.username, url: user.pfpUrl),
                                title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text(user.userId, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
                                trailing: IconButton(
                                  tooltip: 'Message ${user.username}',
                                  onPressed: () => _start(user),
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: _brandBlue),
                                ),
                                onTap: () => showModalBottomSheet<void>(
                                  context: context,
                                  showDragHandle: true,
                                  builder: (_) => SafeArea(child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        _Avatar(label: user.username, url: user.pfpUrl, size: 58),
                                        const SizedBox(width: 14),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(user.username, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                                          Text(user.userId, style: const TextStyle(color: _muted, fontSize: 12)),
                                        ])),
                                      ]),
                                      const SizedBox(height: 18),
                                      SizedBox(width: double.infinity, child: FilledButton.icon(
                                        onPressed: () { Navigator.pop(context); _start(user); },
                                        icon: const Icon(Icons.chat_rounded), label: const Text('Start conversation'),
                                      )),
                                    ]),
                                  )),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({
    required this.api,
    required this.crypto,
    required this.uid,
    required this.username,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onSignOut,
  });
  final ApiClient api;
  final CryptoService crypto;
  final String uid;
  final String username;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final Future<void> Function() onSignOut;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic> _profile = {};
  Map<String, bool> _privacy = {
    'showOnlineStatus': true,
    'readReceipts': true,
    'allowDiscovery': true,
    'allowGroupInvites': true,
  };
  bool _loading = true;
  bool _busy = false;
  final _pfp = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) setState(() {});
  }

  @override
  void dispose() {
    _pfp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([widget.api.getMyProfile(), widget.api.getPrivacy()]);
      final profile = asJsonMap(results[0]['user']);
      final privacy = asJsonMap(results[1]['privacy']);
      if (mounted) setState(() {
        _profile = profile;
        _pfp.text = stringValue(profile['pfpUrl']);
        _privacy = {
          'showOnlineStatus': privacy['showOnlineStatus'] != false,
          'readReceipts': privacy['readReceipts'] != false,
          'allowDiscovery': privacy['allowDiscovery'] != false,
          'allowGroupInvites': privacy['allowGroupInvites'] != false,
        };
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _updatePrivacy(String key, bool value) async {
    final old = _privacy[key] ?? true;
    setState(() => _privacy[key] = value);
    try {
      final result = asJsonMap((await widget.api.updatePrivacy({key: value}))['privacy']);
      if (mounted) setState(() => _privacy = {
        'showOnlineStatus': result['showOnlineStatus'] != false,
        'readReceipts': result['readReceipts'] != false,
        'allowDiscovery': result['allowDiscovery'] != false,
        'allowGroupInvites': result['allowGroupInvites'] != false,
      });
    } catch (error) {
      if (mounted) setState(() => _privacy[key] = old);
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _saveProfile() async {
    final url = _pfp.text.trim();
    if (url.isNotEmpty && Uri.tryParse(url)?.scheme != 'https') {
      _showSnack(context, 'Profile picture URL must use HTTPS.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.patchMyProfile(pfpUrl: url);
      await _load();
      if (mounted) _showSnack(context, 'Profile updated.');
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    final controller = TextEditingController();
    var password = '';
    // Existing password is not retained by design. A fresh encrypted backup uses the
    // authenticated account password, so ask for it instead of storing it on the device.
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refresh encrypted backup'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Account password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Encrypt & save')),
        ],
      ),
    );
    password = result ?? '';
    controller.dispose();
    if (password.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.crypto.syncIdentity(uid: widget.uid, username: widget.username, password: password, api: widget.api, forceBackup: true);
      if (mounted) _showSnack(context, 'Encrypted recovery backup refreshed.');
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 10),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
            const SizedBox(height: 10),
            TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, [current.text, next.text, confirm.text]), child: const Text('Update')),
        ],
      ),
    );
    final vals = result;
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (vals == null) return;
    if (vals[1].length < 10 || vals[1].length > 128 || vals[1] != vals[2]) {
      _showSnack(context, 'New passwords must match and be 10–128 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      final backup = await widget.crypto.makePasswordBackup(widget.uid, widget.username, vals[1]);
      final publicKey = (await widget.crypto.localPublicKey(widget.uid)) ?? '';
      await widget.api.changePassword(
        currentPassword: vals[0],
        newPassword: vals[1],
        encryptedBackup: backup,
        publicKey: publicKey,
      );
      await widget.onSignOut();
      if (mounted) _showSnack(context, 'Password changed. Sign in with the new password.');
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This removes the account and account-owned profile, keys, backups, presence, and sessions. Shared conversation copies may remain for other members. This cannot be undone.'),
          const SizedBox(height: 14),
          TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm with your password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteAccount(password);
      await widget.crypto.deleteIdentity(widget.uid);
      await widget.api.clearSession();
      if (mounted) await widget.onSignOut();
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apiStatus() async {
    try {
      final result = await widget.api.health();
      if (!mounted) return;
      showDialog<void>(context: context, builder: (_) => AlertDialog(
        title: const Text('CrazeChat API'),
        content: Text('Service: ${stringValue(result['service'])}\nDatabase: ${stringValue(result['database'], 'unknown')}\nStorage: ${stringValue(result['storage'], 'unknown')}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } catch (error) {
      if (mounted) _showSnack(context, 'API check failed: $error');
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    _showSnack(context, '$label copied.');
  }

  @override
  Widget build(BuildContext context) {
    final publicKey = stringValue(_profile['publicKey']).split('::ENC::').first;
    final fingerprint = publicKey.isEmpty ? 'No key available' : _fingerprint(publicKey);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.5))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      _Avatar(label: widget.username, url: stringValue(_profile['pfpUrl']), size: 62),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.username, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('CrazeChat account', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Text('ID  ${widget.uid}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _muted)),
                      ])),
                      IconButton(onPressed: () => _copy(widget.uid, 'User ID'), tooltip: 'Copy user ID', icon: const Icon(Icons.copy_rounded)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(title: 'Profile', icon: Icons.person_outline_rounded, children: [
                  TextField(
                    controller: _pfp,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Profile picture URL', hintText: 'https://example.com/avatar.png'),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: _busy ? null : _saveProfile,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save profile'),
                  )),
                ]),
                _SectionCard(title: 'Appearance', icon: Icons.palette_outlined, children: [
                  DropdownButtonFormField<ThemeMode>(
                    value: widget.themeMode,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('Follow system')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    ],
                    onChanged: (mode) { if (mode != null) widget.onThemeChanged(mode); },
                  ),
                ]),
                _SectionCard(title: 'Privacy', icon: Icons.shield_outlined, children: [
                  _PrivacyRow(title: 'Show online status', subtitle: 'Let other members see when you are online.', value: _privacy['showOnlineStatus']!, onChanged: (v) => _updatePrivacy('showOnlineStatus', v)),
                  _PrivacyRow(title: 'Read receipts', subtitle: 'Share that you have seen messages.', value: _privacy['readReceipts']!, onChanged: (v) => _updatePrivacy('readReceipts', v)),
                  _PrivacyRow(title: 'Profile discovery', subtitle: 'Allow your profile to appear in People search.', value: _privacy['allowDiscovery']!, onChanged: (v) => _updatePrivacy('allowDiscovery', v)),
                  _PrivacyRow(title: 'Group invitations', subtitle: 'Allow owners to add you to groups.', value: _privacy['allowGroupInvites']!, onChanged: (v) => _updatePrivacy('allowGroupInvites', v)),
                ]),
                _SectionCard(title: 'Encryption & recovery', icon: Icons.key_outlined, children: [
                  const Text('Private keys are stored locally. The server receives encrypted recovery backup data, never the private key in plaintext.', style: TextStyle(color: _muted, height: 1.4, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Public key fingerprint', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      SelectableText(fingerprint, style: const TextStyle(color: _muted, fontSize: 12)),
                    ])),
                    IconButton(tooltip: 'Copy fingerprint', onPressed: () => _copy(fingerprint, 'Fingerprint'), icon: const Icon(Icons.copy_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: _busy ? null : _backup,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Refresh encrypted recovery backup'),
                  )),
                ]),
                _SectionCard(title: 'Security', icon: Icons.lock_outline_rounded, children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Re-encrypt the recovery backup with the new password.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _changePassword,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.monitor_heart_outlined),
                    title: const Text('API status', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Check the Vercel API and database connection.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _apiStatus,
                  ),
                ]),
                _SectionCard(title: 'Account', icon: Icons.manage_accounts_outlined, children: [
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  )),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: _busy ? null : _deleteAccount,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete account permanently'),
                  )),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.all(10), child: Center(child: CircularProgressIndicator())),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                  child: Text('CrazeChat · Private conversations, carefully built.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
                ),
              ],
            ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: _brandBlue.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: _brandBlue),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 16),
            ...children,
          ]),
        ),
      );
}

class _RenderedMessage {
  const _RenderedMessage({required this.message, required this.text, this.seen = false});
  final ChatMessage message;
  final String text;
  final bool seen;
}

class _ChatScreen extends StatefulWidget {
  const _ChatScreen({
    required this.api,
    required this.crypto,
    required this.uid,
    required this.username,
    required this.chatId,
    required this.fallbackTitle,
  });
  final ApiClient api;
  final CryptoService crypto;
  final String uid;
  final String username;
  final String chatId;
  final String fallbackTitle;

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  ChatRecord? _chat;
  List<_RenderedMessage> _messages = [];
  ChatMessage? _replyTo;
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  int _ttl = 1440;
  String? _error;
  final Set<String> _seenSent = {};
  final Map<String, bool> _seenByOthers = {};
  final Map<String, String> _publicKeyCache = {};

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _publicKeyFor(String uid) async {
    final cached = _publicKeyCache[uid];
    if (cached != null && cached.isNotEmpty) return cached;
    final profile = asJsonMap((await widget.api.getUser(uid))['user']);
    final key = stringValue(profile['publicKey']).split('::ENC::').first;
    if (key.isEmpty) throw StateError('The other account has not synced an encryption key yet.');
    _publicKeyCache[uid] = key;
    return key;
  }

  Future<String> _decrypt(ChatMessage message, ChatRecord chat) async {
    if (message.nonce.isEmpty) {
      // Some older prototypes stored unencrypted text in this field; keep it visible as legacy data.
      return message.ciphertext;
    }
    if (chat.isGroup) {
      if (widget.crypto.groupMessageVersion(message.ciphertext) > 0) {
        return widget.crypto.decryptGroup(uid: widget.uid, api: widget.api, chatId: chat.id, ciphertext: message.ciphertext, nonce: message.nonce);
      }
      return widget.crypto.decryptLegacyGroup(chat.id, message.ciphertext, message.nonce);
    }
    final peerId = message.senderUid == widget.uid
        ? chat.memberIds.firstWhere((id) => id != widget.uid, orElse: () => '')
        : message.senderUid;
    if (peerId.isEmpty) throw StateError('Direct chat membership is incomplete.');
    return widget.crypto.decryptDirect(widget.uid, await _publicKeyFor(peerId), message.ciphertext, message.nonce);
  }

  Future<void> _load({bool quiet = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!quiet && mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var chat = ChatRecord.fromJson(asJsonMap((await widget.api.getChat(widget.chatId))['chat']));
      if (chat.isGroup && chat.groupKeyVersion == 0 && chat.createdBy == widget.uid) {
        await widget.crypto.rotateGroupKey(uid: widget.uid, username: widget.username, api: widget.api, chat: chat);
        chat = ChatRecord.fromJson(asJsonMap((await widget.api.getChat(widget.chatId))['chat']));
      }
      final rawMessages = await widget.api.getMessages(widget.chatId, limit: 100);
      final rendered = <_RenderedMessage>[];
      for (final raw in rawMessages) {
        final message = ChatMessage.fromJson(raw);
        if (message.isDeleted) continue;
        String text;
        try {
          text = await _decrypt(message, chat);
        } catch (_) {
          text = '[Encrypted message unavailable on this device]';
        }
        var seen = message.receipts.keys.any((key) => key != message.senderUid);
        if (message.senderUid != widget.uid && !_seenSent.contains(message.id)) {
          _seenSent.add(message.id);
          unawaited(widget.api.markSeen(message.id).catchError((_) => <String, dynamic>{}));
        }
        if (message.senderUid == widget.uid && !seen && (_seenByOthers[message.id] != true)) {
          try {
            final seenResponse = await widget.api.getSeen(message.id);
            seen = seenResponse['seen'] == true;
            _seenByOthers[message.id] = seen;
          } catch (_) {}
        }
        rendered.add(_RenderedMessage(message: message, text: text, seen: seen));
      }
      if (!mounted) return;
      setState(() {
        _chat = chat;
        _messages = rendered;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<Map<String, String>> _encrypt(String text) async {
    final chat = _chat;
    if (chat == null) throw StateError('Conversation is still loading.');
    if (chat.isGroup) {
      if (chat.groupKeyVersion < 1) {
        if (chat.createdBy == widget.uid) {
          await widget.crypto.rotateGroupKey(uid: widget.uid, username: widget.username, api: widget.api, chat: chat);
          await _load(quiet: true);
        } else {
          throw StateError('This group has no active encryption key yet. Ask the group owner to refresh it.');
        }
      }
      final latest = ChatRecord.fromJson(asJsonMap((await widget.api.getChat(widget.chatId))['chat']));
      if (latest.groupKeyVersion < 1) throw StateError('Group encryption key is not ready.');
      return widget.crypto.encryptGroup(uid: widget.uid, api: widget.api, chatId: latest.id, version: latest.groupKeyVersion, plaintext: text);
    }
    final peerId = chat.memberIds.firstWhere((id) => id != widget.uid, orElse: () => '');
    if (peerId.isEmpty) throw StateError('Direct chat membership is incomplete.');
    return widget.crypto.encryptDirect(widget.uid, await _publicKeyFor(peerId), text);
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final encrypted = await _encrypt(text);
      final chat = _chat!;
      final peerId = chat.isGroup ? null : chat.memberIds.firstWhere((id) => id != widget.uid, orElse: () => '');
      await widget.api.sendMessage(
        chatId: chat.id,
        ciphertext: encrypted['ciphertext']!,
        nonce: encrypted['nonce']!,
        ttlMinutes: _ttl,
        replyToId: _replyTo?.id,
        replyToSender: _replyTo == null ? null : _replyTo!.senderUsername,
        receiverId: peerId,
      );
      _composer.clear();
      setState(() => _replyTo = null);
      await _load(quiet: true);
      if (_scroll.hasClients) await _scroll.animateTo(_scroll.position.maxScrollExtent + 180, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(_RenderedMessage item) async {
    if (item.message.nonce.isEmpty) {
      _showSnack(context, 'Legacy messages cannot be edited using the encrypted message API.');
      return;
    }
    final controller = TextEditingController(text: item.text.startsWith('[') ? '' : item.text);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, minLines: 1, maxLines: 6, autofocus: true, decoration: const InputDecoration(hintText: 'Message')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (edited == null || edited.isEmpty) return;
    try {
      final payload = await _encrypt(edited);
      await widget.api.editMessage(item.message.id, payload['ciphertext']!, payload['nonce']!);
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _delete(_RenderedMessage item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('The server will remove this message from the conversation index.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.api.deleteMessage(item.message.id);
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _togglePin(_RenderedMessage item) async {
    try {
      await widget.api.pinMessage(item.message.id, !item.message.pinned);
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _react(_RenderedMessage item, String emoji) async {
    try {
      if (item.message.reactions[widget.uid] == emoji) {
        await widget.api.removeReaction(item.message.id);
      } else {
        await widget.api.reactToMessage(item.message.id, emoji);
      }
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _messageActions(_RenderedMessage item) async {
    final mine = item.message.senderUid == widget.uid;
    final chat = _chat;
    if (chat == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(item.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 15),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 9,
              children: ['❤️', '😂', '👍', '😮', '😢', '🔥'].map((emoji) => ActionChip(
                label: Text(emoji, style: const TextStyle(fontSize: 19)),
                onPressed: () { Navigator.pop(sheetContext); _react(item, emoji); },
              )).toList(),
            ),
            const Divider(height: 22),
            ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () {
              Navigator.pop(sheetContext);
              setState(() => _replyTo = item.message);
            }),
            if (mine) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit message'), onTap: () {
              Navigator.pop(sheetContext);
              _edit(item);
            }),
            ListTile(
              leading: Icon(item.message.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
              title: Text(item.message.pinned ? 'Unpin message' : 'Pin message'),
              onTap: () { Navigator.pop(sheetContext); _togglePin(item); },
            ),
            if (mine || !chat.isGroup) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Delete message'),
              onTap: () { Navigator.pop(sheetContext); _delete(item); },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _groupActions() async {
    final chat = _chat;
    if (chat == null || !chat.isGroup) return;
    final isOwner = chat.createdBy == widget.uid;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.groups_outlined), title: Text('${chat.memberIds.length} members'), subtitle: Text(isOwner ? 'You are the group owner' : 'Group conversation')),
          if (isOwner) ListTile(leading: const Icon(Icons.person_add_alt_1_rounded), title: const Text('Add member'), onTap: () {
            Navigator.pop(sheetContext);
            _addMember();
          }),
          if (isOwner) ListTile(leading: const Icon(Icons.key_rounded), title: const Text('Rotate group encryption key'), subtitle: const Text('Recommended after membership changes.'), onTap: () {
            Navigator.pop(sheetContext);
            _rotateGroup();
          }),
          if (chat.pinnedMessageId.isNotEmpty) ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('A message is pinned'), subtitle: Text(chat.pinnedMessageId)),
        ]),
      ),
    );
  }

  Future<void> _rotateGroup() async {
    final chat = _chat;
    if (chat == null) return;
    try {
      await widget.crypto.rotateGroupKey(uid: widget.uid, username: widget.username, api: widget.api, chat: chat);
      await _load();
      if (mounted) _showSnack(context, 'Group encryption key rotated.');
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    }
  }

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add group member'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Username or user ID')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (target == null || target.isEmpty) return;
    try {
      final user = await _resolveUser(widget.api, target);
      await widget.api.addGroupMember(widget.chatId, user.userId);
      final updated = ChatRecord.fromJson(asJsonMap((await widget.api.getChat(widget.chatId))['chat']));
      await widget.crypto.rotateGroupKey(uid: widget.uid, username: widget.username, api: widget.api, chat: updated);
      await _load();
      if (mounted) _showSnack(context, '${user.username} added and group key rotated.');
    } catch (error) {
      if (mounted) _showSnack(context, 'Member update: $error');
    }
  }

  void _chooseTtl() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Message retention', style: TextStyle(fontWeight: FontWeight.w900))),
        for (final option in const [
          (60, '1 hour'),
          (1440, '24 hours'),
          (4320, '3 days'),
          (10080, '7 days'),
        ])
          RadioListTile<int>(
            value: option.$1,
            groupValue: _ttl,
            title: Text(option.$2),
            onChanged: (value) { if (value != null) setState(() => _ttl = value); Navigator.pop(context); },
          ),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final title = chat?.title.isNotEmpty == true ? chat!.title : widget.fallbackTitle;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
        title: Row(children: [
          _Avatar(label: title, group: chat?.isGroup ?? false, size: 40),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(chat?.isGroup == true ? '${chat!.memberIds.length} members' : 'Private conversation', style: const TextStyle(color: _muted, fontSize: 11)),
          ])),
        ]),
        actions: [
          IconButton(tooltip: 'Message retention', onPressed: _chooseTtl, icon: const Icon(Icons.timer_outlined)),
          if (chat?.isGroup == true) IconButton(tooltip: 'Group options', onPressed: _groupActions, icon: const Icon(Icons.more_vert_rounded)),
        ],
      ),
      body: Column(children: [
        if (_error != null && _messages.isEmpty)
          MaterialBanner(
            content: Text(_error!),
            leading: const Icon(Icons.cloud_off_outlined),
            actions: [TextButton(onPressed: () => _load(), child: const Text('Retry'))],
          ),
        if (chat?.pinnedMessageId.isNotEmpty == true)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            color: _brandBlue.withOpacity(.08),
            child: const Row(children: [
              Icon(Icons.push_pin_rounded, size: 16, color: _brandBlue),
              SizedBox(width: 8),
              Expanded(child: Text('A message is pinned in this conversation.', style: TextStyle(fontSize: 12))),
            ]),
          ),
        Expanded(
          child: _loading && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const _EmptyState(icon: Icons.waving_hand_outlined, title: 'Say hello 👋', detail: 'Your messages are encrypted on your device before being sent.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final item = _messages[index];
                          final mine = item.message.senderUid == widget.uid;
                          final reactions = item.message.reactions.values.toSet().join(' ');
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _messageActions(item),
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                                margin: const EdgeInsets.only(bottom: 9),
                                padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
                                decoration: BoxDecoration(
                                  color: mine ? _brandBlue : Theme.of(context).colorScheme.surface,
                                  border: mine ? null : Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : _lightBorder),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(mine ? 18 : 5),
                                    bottomRight: Radius.circular(mine ? 5 : 18),
                                  ),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  if (chat?.isGroup == true && !mine)
                                    Align(alignment: Alignment.centerLeft, child: Text(item.message.senderUsername, style: const TextStyle(fontWeight: FontWeight.w800, color: _brandBlue, fontSize: 11))),
                                  if (item.message.replyToId.isNotEmpty)
                                    Align(alignment: Alignment.centerLeft, child: Text('↪ Reply to message', style: TextStyle(color: mine ? Colors.white70 : _muted, fontSize: 11))),
                                  if (item.message.pinned)
                                    Align(alignment: Alignment.centerLeft, child: Icon(Icons.push_pin_rounded, size: 13, color: mine ? Colors.white70 : _brandBlue)),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      item.text,
                                      style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface, height: 1.38),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (item.message.editedAt != null)
                                      Text('edited · ', style: TextStyle(color: mine ? Colors.white70 : _muted, fontSize: 9)),
                                    Text(DateFormat('HH:mm').format(item.message.createdAt), style: TextStyle(color: mine ? Colors.white70 : _muted, fontSize: 10)),
                                    if (mine) ...[
                                      const SizedBox(width: 4),
                                      Icon(item.seen ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: item.seen ? const Color(0xFFB3E5FC) : Colors.white70),
                                    ],
                                  ]),
                                  if (reactions.isNotEmpty)
                                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(reactions, style: const TextStyle(fontSize: 14))),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
        if (_replyTo != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _brandBlue.withOpacity(.09), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.reply_rounded, color: _brandBlue, size: 19),
              const SizedBox(width: 8),
              Expanded(child: Text('Replying to ${_replyTo!.senderUsername.isEmpty ? 'message' : _replyTo!.senderUsername}: ${_messages.firstWhere((item) => item.message.id == _replyTo!.id, orElse: () => _RenderedMessage(message: _replyTo!, text: 'Message')).text}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              IconButton(onPressed: () => setState(() => _replyTo = null), icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: 'Message retention',
                onPressed: _chooseTtl,
                icon: const Icon(Icons.timer_outlined, color: _muted),
              ),
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    suffixIcon: IconButton(tooltip: 'Emoji reactions are available on sent messages', onPressed: () => _showSnack(context, 'Long-press a message to react.'), icon: const Icon(Icons.add_reaction_outlined)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                height: 52,
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

Future<UserProfile> _resolveUser(ApiClient api, String query) async {
  final input = query.trim();
  if (input.isEmpty) throw const ApiException(400, 'Enter a username or user ID.');
  try {
    return UserProfile.fromJson(asJsonMap((await api.getUserByUsername(input))['user']));
  } on ApiException catch (error) {
    if (error.status != 404) rethrow;
  }
  return UserProfile.fromJson(asJsonMap((await api.getUser(input))['user']));
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, this.url = '', this.group = false, this.size = 50});
  final String label;
  final String url;
  final bool group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final goodUrl = url.startsWith('https://');
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFEFF6FF),
      backgroundImage: goodUrl ? NetworkImage(url) : null,
      child: goodUrl ? null : Icon(group ? Icons.groups_rounded : Icons.person_rounded, color: _brandBlue, size: size * .48),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.detail, this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(color: _brandBlue.withOpacity(.09), borderRadius: BorderRadius.circular(24)),
                child: Icon(icon, size: 34, color: _brandBlue),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.5, fontSize: 13)),
              if (action != null) ...[const SizedBox(height: 12), action!],
            ]),
          ),
        ),
      );
}

String _friendlyTime(DateTime value) {
  if (value.year < 2000) return '';
  final now = DateTime.now();
  if (now.difference(value).inDays == 0 && now.day == value.day) return DateFormat('HH:mm').format(value);
  if (now.difference(value).inDays < 7) return DateFormat('EEE').format(value);
  return DateFormat('dd/MM').format(value);
}

String _fingerprint(String publicKey) {
  final digest = crypto.sha256.convert(utf8.encode(publicKey)).bytes;
  return digest
      .take(8)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase()
      .replaceAllMapped(RegExp(r'(.{4})'), (match) => '${match[1]} ');
}

void _showSnack(BuildContext context, String message) {
  final snack = ScaffoldMessenger.maybeOf(context);
  if (snack == null) return;
  snack.hideCurrentSnackBar();
  snack.showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
