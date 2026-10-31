import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'crypto_service.dart';
import 'session.dart';

class CrazeChatApp extends StatefulWidget {
  const CrazeChatApp({super.key});
  @override
  State<CrazeChatApp> createState() => _CrazeChatAppState();
}

class _CrazeChatAppState extends State<CrazeChatApp> {
  final session = ChatSession();
  @override
  void initState() { super.initState(); session.restore(); }
  @override
  void dispose() { session.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF087E65);
    return MaterialApp(
      title: 'CrazeChat',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF7F8F7),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0),
        cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFFF1F3F2),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        cardTheme: CardThemeData(color: const Color(0xFF121E32), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      ),
      home: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          if (!session.ready) return const _LoadingScreen();
          if (!session.signedIn) return AuthScreen(session: session);
          if (!session.unlocked) return UnlockScreen(session: session);
          return HomeScreen(session: session);
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.session});
  final ChatSession session;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool creating = false, busy = false, showPassword = false;

  @override
  void dispose() { username.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    final name = username.text.trim();
    final pass = password.text;
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(name)) {
      showMessage(context, 'Username: 3–20 letters, numbers, or underscores.'); return;
    }
    if (creating && pass.length < 12) { showMessage(context, 'Use a password with at least 12 characters.'); return; }
    if (pass.isEmpty) { showMessage(context, 'Enter your password.'); return; }
    setState(() => busy = true);
    try {
      late final Map<String, dynamic> result;
      late final KeyPair keyPair;
      if (creating) {
        final material = await CryptoService.createIdentity(pass);
        result = await widget.session.api.post('/auth/register', {
          'username': name, 'password': pass,
          'publicKey': material.envelope['publicKey'],
          'identityEnvelope': material.envelope,
        });
        keyPair = material.keyPair;
      } else {
        result = await widget.session.api.post('/auth/login', {'username': name, 'password': pass});
        keyPair = await CryptoService.unlockIdentity(
          Map<String, dynamic>.from(result['identityEnvelope'] as Map), pass,
        );
      }
      await widget.session.acceptSession(result, keyPair);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, creating ? 'Account setup failed. Check the API and try again.' : 'Password could not unlock this account.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 76, height: 76,
                  decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 42)),
                const SizedBox(height: 24),
                Text('CrazeChat', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Your conversations. Your keys. Your privacy.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 34),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Sign in'), icon: Icon(Icons.login)),
                    ButtonSegment(value: true, label: Text('Create account'), icon: Icon(Icons.person_add_alt_1)),
                  ],
                  selected: {creating},
                  onSelectionChanged: busy ? null : (v) => setState(() => creating = v.first),
                ),
                const SizedBox(height: 22),
                TextField(controller: username, autocorrect: false, textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email))),
                const SizedBox(height: 14),
                TextField(controller: password, obscureText: !showPassword,
                  decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(onPressed: () => setState(() => showPassword = !showPassword),
                      icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility))),
                  onSubmitted: (_) => submit()),
                if (creating) ...[
                  const SizedBox(height: 10),
                  Text('Use 12+ characters. This password protects your private encryption key. If you lose it and have no unlocked device, your messages cannot be recovered.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: busy ? null : submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 17)),
                  child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(creating ? 'Create secure account' : 'Unlock and sign in')),
                const SizedBox(height: 22),
                const _SecurityNote(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Icon(Icons.shield_outlined, color: Color(0xFF16A36A), size: 20),
    const SizedBox(width: 10),
    Expanded(child: Text('Messages are encrypted on your device before upload. The server stores ciphertext, not readable message text.',
      style: Theme.of(context).textTheme.bodySmall)),
  ]);
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.session});
  final ChatSession session;
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final password = TextEditingController();
  bool busy = false, visible = false;
  @override
  void dispose() { password.dispose(); super.dispose(); }

  Future<void> unlock() async {
    setState(() => busy = true);
    try { await widget.session.unlock(password.text); }
    catch (_) { if (mounted) showMessage(context, 'Incorrect password or damaged encrypted key backup.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.lock_person_outlined, size: 64),
          const SizedBox(height: 18),
          Text('Welcome back, @' + widget.session.username!, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Enter your password to decrypt your private identity key on this device.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(controller: password, obscureText: !visible, onSubmitted: (_) => unlock(),
            decoration: InputDecoration(labelText: 'Account password', prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(onPressed: () => setState(() => visible = !visible),
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility)))),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : unlock,
            child: busy ? const CircularProgressIndicator() : const Text('Unlock CrazeChat')),
          TextButton(onPressed: widget.session.signOut, child: const Text('Sign in to another account')),
        ]),
      ),
    ))),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final ChatSession session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> chats = [];
  bool loading = true;
  @override
  void initState() { super.initState(); loadChats(); }

  Future<void> loadChats() async {
    try {
      final data = await widget.session.api.get('/chats');
      final list = (data['chats'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map)).toList();
      if (mounted) setState(() { chats = list; loading = false; });
    } catch (e) {
      if (mounted) { setState(() => loading = false); showMessage(context, e.toString()); }
    }
  }

  Future<void> startChat() async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a conversation'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(labelText: 'CrazeChat username', prefixIcon: Icon(Icons.alternate_email)),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Find user')),
        ],
      ),
    );
    controller.dispose();
    if (target == null || target.isEmpty || !mounted) return;
    try {
      final response = await widget.session.api.post('/chats', {'username': target});
      await openChat(Map<String, dynamic>.from(response['chat'] as Map));
    } catch (e) { if (mounted) showMessage(context, e.toString()); }
  }

  Future<void> openChat(Map<String, dynamic> chat) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(session: widget.session, chat: chat)));
    if (mounted) loadChats();
  }

  Future<void> showAccountMenu() async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('@' + widget.session.username!, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Your direct messages are end-to-end encrypted.'),
          const SizedBox(height: 18),
          ...widget.session.savedAccounts.where((account) => account['userId'] != widget.session.userId).map((account) =>
            ListTile(leading: const Icon(Icons.switch_account), title: Text('@${account['username']}'),
              subtitle: const Text('Switch account'), onTap: () {
                Navigator.pop(sheetContext);
                widget.session.switchAccount(account['userId'] as String);
              })),
          if (widget.session.savedAccounts.length < 2)
            ListTile(leading: const Icon(Icons.person_add_alt_1), title: const Text('Add another account'),
              onTap: () { Navigator.pop(sheetContext); widget.session.addAccount(); }),
          ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Lock app'),
            onTap: () { Navigator.pop(sheetContext); widget.session.lock(); }),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out this account'),
            onTap: () { Navigator.pop(sheetContext); widget.session.signOut(); }),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: const Text('CrazeChat', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.7)), 
        actions: [
          IconButton(onPressed: startChat, tooltip: 'New conversation', icon: const Icon(Icons.edit_square)),
          IconButton(onPressed: showAccountMenu, tooltip: 'Account', icon: const Icon(Icons.account_circle_outlined)),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: startChat, icon: const Icon(Icons.add_comment_outlined), label: const Text('New chat')),
      body: RefreshIndicator(
        onRefresh: loadChats,
        child: loading ? const Center(child: CircularProgressIndicator())
          : chats.isEmpty ? ListView(children: [
              const SizedBox(height: 100),
              Icon(Icons.forum_outlined, size: 72, color: colors.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 18),
              Text('Your inbox is quiet', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Start a new chat with a CrazeChat username.', textAlign: TextAlign.center),
              const SizedBox(height: 22),
              Center(child: FilledButton.icon(onPressed: startChat, icon: const Icon(Icons.add), label: const Text('Find someone'))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: chats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final chat = chats[index];
                final members = (chat['members'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map));
                Map<String, dynamic>? peer;
                for (final member in members) {
                  if (member['id'] != widget.session.userId) { peer = member; break; }
                }
                final name = peer?['username']?.toString() ?? 'Unknown user';
                return Card(child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(backgroundColor: colors.primaryContainer,
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(color: colors.onPrimaryContainer, fontWeight: FontWeight.bold))),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Row(children: [Icon(Icons.lock, size: 13), SizedBox(width: 5), Text('End-to-end encrypted')]),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openChat(chat),
                ));
              },
            ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.session, required this.chat});
  final ChatSession session;
  final Map<String, dynamic> chat;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  final Set<String> messageIds = <String>{};
  SecretKey? chatKey;
  String? peerName, error;
  bool loading = true, sending = false, syncing = false;
  int? lastMessageAt, lastPurgeAt;
  final Set<String> purgeIds = <String>{};
  Timer? poller;
  String get chatId => widget.chat['id'] as String;

  Map<String, dynamic>? get peer {
    final members = (widget.chat['members'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map));
    for (final member in members) {
      if (member['id'] != widget.session.userId) return member;
    }
    return null;
  }

  @override
  void initState() { super.initState(); prepare(); }
  @override
  void dispose() { poller?.cancel(); input.dispose(); scroll.dispose(); super.dispose(); }

  Future<void> prepare() async {
    final other = peer;
    if (other == null || widget.session.identity == null) {
      setState(() { error = 'This conversation is missing its encryption identity.'; loading = false; });
      return;
    }
    peerName = other['username']?.toString() ?? 'Chat';
    try {
      chatKey = await CryptoService.deriveChatKey(
        myKeyPair: widget.session.identity!,
        peerPublicKey: other['publicKey'] as String,
        chatId: chatId,
      );
      await loadMessages();
      poller = Timer.periodic(const Duration(seconds: 3), (_) => loadMessages(silent: true));
    } catch (_) {
      if (mounted) setState(() { error = 'Could not establish the encrypted chat key.'; loading = false; });
    }
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (chatKey == null || syncing) return;
    syncing = true;
    try {
      final results = await Future.wait([
        widget.session.api.getMessages(
          chatId, since: lastMessageAt == null ? null : lastMessageAt! - 1,
          limit: lastMessageAt == null ? 50 : 100,
        ),
        widget.session.api.getPurgedMessages(chatId, since: lastPurgeAt == null ? null : lastPurgeAt! - 1),
      ]);
      final response = results[0];
      final purges = results[1] as Map<String, int>;
      final raw = (response['messages'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map)).toList();
      final fresh = raw.where((message) => message['id'] is String && !messageIds.contains(message['id'])).toList();
      final decoded = <Map<String, dynamic>>[];
      for (final message in fresh) {
        try {
          final clear = await CryptoService.decryptMessage(message: message, chatKey: chatKey!, chatId: chatId);
          decoded.add({...message, 'clearText': clear});
        } catch (_) { decoded.add({...message, 'clearText': 'Unable to decrypt this message'}); }
      }
      if (!mounted) return;
      if (decoded.isNotEmpty) {
        decoded.sort((a, b) => (a['createdAt'] as num).compareTo(b['createdAt'] as num));
        setState(() {
          messages.addAll(decoded);
          for (final item in decoded) {
            messageIds.add(item['id'] as String);
            final timestamp = (item['createdAt'] as num?)?.toInt() ?? 0;
            if (lastMessageAt == null || timestamp > lastMessageAt!) lastMessageAt = timestamp;
          }
          for (final entry in purges.entries) {
            if (!purgeIds.add(entry.key)) { continue; }
            messages.removeWhere((item) => item['id'] == entry.key);
            messageIds.remove(entry.key);
          }
          lastPurgeAt = DateTime.now().millisecondsSinceEpoch - 2000;
          messages.sort((a, b) => (a['createdAt'] as num).compareTo(b['createdAt'] as num));
          loading = false; error = null;
        });
        if (!silent && scroll.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scroll.hasClients) { scroll.animateTo(scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180), curve: Curves.easeOut); }
          });
        }
      } else if (mounted && (loading || purges.isNotEmpty)) {
        setState(() {
          for (final entry in purges.entries) {
            if (!purgeIds.add(entry.key)) continue;
            messages.removeWhere((item) => item['id'] == entry.key);
            messageIds.remove(entry.key);
          }
          lastPurgeAt = DateTime.now().millisecondsSinceEpoch - 2000;
          loading = false; error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() { error = e.toString(); loading = false; });
    } finally {
      syncing = false;
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending || chatKey == null) return;
    setState(() => sending = true);
    input.clear();
    try {
      final encrypted = await CryptoService.encryptMessage(
        text: text, chatKey: chatKey!, chatId: chatId, senderId: widget.session.userId!,
      );
      final response = await widget.session.api.post('/chats/$chatId/messages', encrypted);
      final sent = Map<String, dynamic>.from(response['message'] as Map);
      final clear = await CryptoService.decryptMessage(message: sent, chatKey: chatKey!, chatId: chatId);
      if (mounted && !messageIds.contains(sent['id'])) {
        setState(() {
          messages.add({...sent, 'clearText': clear});
          messageIds.add(sent['id'] as String);
          final timestamp = (sent['createdAt'] as num?)?.toInt() ?? 0;
          if (lastMessageAt == null || timestamp > lastMessageAt!) lastMessageAt = timestamp;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) { scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut); }
        });
      }
    } catch (e) {
      input.text = text;
      if (mounted) showMessage(context, e.toString());
    } finally { if (mounted) setState(() => sending = false); }
  }

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    final messageId = message['id']?.toString();
    if (messageId == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(messageId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This permanently removes the message from the server and both chat inboxes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session.api.delete('/chats/$chatId/messages/$messageId');
      if (!mounted) return;
      setState(() { messages.removeWhere((item) => item['id'] == messageId); messageIds.remove(messageId); });
      showMessage(context, 'Message permanently deleted from the server.');
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    }
  }
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        CircleAvatar(backgroundColor: colors.primaryContainer,
          child: Text((peerName ?? '?').isEmpty ? '?' : (peerName ?? '?')[0].toUpperCase())),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(peerName ?? 'Conversation', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Row(children: [Icon(Icons.lock, size: 12, color: Color(0xFF16A36A)), SizedBox(width: 4),
            Text('End-to-end encrypted', style: TextStyle(fontSize: 11))]),
        ])),
      ])),
      body: Container(color: const Color(0xFFECE9E2), child: Column(children: [
        Expanded(
          child: loading ? const Center(child: CircularProgressIndicator())
            : error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
            : messages.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline, size: 48, color: colors.primary),
                const SizedBox(height: 12),
                const Text('This chat is private', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Messages are encrypted before leaving your device.', textAlign: TextAlign.center),
              ])))
            : ListView.builder(
                controller: scroll, padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final mine = message['senderId'] == widget.session.userId;
                  return GestureDetector(
                    onLongPress: mine ? () => deleteMessage(message) : null,
                    child: Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: mine ? const Color(0xFFD8F5E7) : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(mine ? 18 : 5), bottomRight: Radius.circular(mine ? 5 : 18),
                        ),
                      ),
                        child: Text(message['clearText']?.toString() ?? '',
                          style: TextStyle(color: mine ? colors.onPrimary : colors.onSurface)),
                      ),
                    ),
                  );
                },
              ),
        ),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            Expanded(child: TextField(
              controller: input, minLines: 1, maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message', prefixIcon: Icon(Icons.emoji_emotions_outlined), fillColor: Colors.white),
              onSubmitted: (_) => send(),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF087E65), foregroundColor: Colors.white, fixedSize: const Size(50, 50)),
              onPressed: sending ? null : send,
              icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            ),
          ]),
        )),
      ])),
    );
  }
}
