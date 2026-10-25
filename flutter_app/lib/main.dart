import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'firebase_options.dart';

const blue = Color(0xFF2563EB);
const muted = Color(0xFF64748B);
const uuid = Uuid();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CrazeChatApp());
}

DatabaseReference get db => FirebaseDatabase.instance.ref();

ThemeData makeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      surface: dark ? const Color(0xFF1E293B) : Colors.white,
    ),
    scaffoldBackgroundColor: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      foregroundColor: dark ? Colors.white : const Color(0xFF0F172A),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1E293B) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: dark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: blue, width: 1.5),
      ),
    ),
  );
}

class CrazeChatApp extends StatefulWidget {
  const CrazeChatApp({super.key});
  @override
  State<CrazeChatApp> createState() => _CrazeChatAppState();
}

class _CrazeChatAppState extends State<CrazeChatApp> {
  String? uid;
  String username = '';
  ThemeMode mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      uid = p.getString('uid');
      username = p.getString('username') ?? '';
      mode = p.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.system;
    });
  }

  Future<void> loginSession(String id, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('uid', id);
    await p.setString('username', name);
    if (mounted) setState(() { uid = id; username = name; });
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('uid');
    await p.remove('username');
    if (mounted) setState(() { uid = null; username = ''; });
  }

  Future<void> setDark(bool dark) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', dark ? 'dark' : 'system');
    if (mounted) setState(() => mode = dark ? ThemeMode.dark : ThemeMode.system);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CrazeChat',
    debugShowCheckedModeBanner: false,
    theme: makeTheme(Brightness.light),
    darkTheme: makeTheme(Brightness.dark),
    themeMode: mode,
    home: uid == null
      ? WelcomePage(onSession: loginSession)
      : HomePage(uid: uid!, username: username, onLogout: logout, onTheme: setDark),
  );
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onSession});
  final Future<void> Function(String, String) onSession;
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final name = TextEditingController();
  final password = TextEditingController();
  bool registering = true, busy = false, hidePassword = true;
  String? error;

  String passwordHash(String value) =>
      sha256.convert(utf8.encode('CrazeChat_Salt_2026_' + value)).toString();

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final cleanName = name.text.trim();
    final pass = password.text;
    if (cleanName.length < 3 || pass.length < 6) {
      setState(() => error = 'Use a username with 3+ characters and a password with 6+ characters.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileKey = 'profile_' + cleanName.toLowerCase();
      final existing = prefs.getString(profileKey);
      if (registering && existing != null) throw Exception('This username already exists on this device.');
      if (!registering && existing == null) throw Exception('No local profile found. Register on this device first.');
      if (registering) {
        final id = uuid.v4();
        await prefs.setString(profileKey, id + '|' + passwordHash(pass));
        await db.child('users/' + id).set({
          'userId': id,
          'username': cleanName,
          'publicKey': '',
          'pfpUrl': '',
          'createdAt': ServerValue.timestamp,
        });
        await widget.onSession(id, cleanName);
      } else {
        final parts = existing!.split('|');
        if (parts.length != 2 || parts[1] != passwordHash(pass)) {
          throw Exception('Incorrect password.');
        }
        await widget.onSession(parts[0], cleanName);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 24, offset: Offset(0, 10))]),
                  child: const Icon(Icons.forum_rounded, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 28),
                const Text('CrazeChat', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
                const SizedBox(height: 8),
                Text(registering ? 'A calmer space for your conversations.' : 'Welcome back. Pick up where you left off.',
                  style: const TextStyle(color: muted, fontSize: 15)),
                const SizedBox(height: 30),
                TextField(controller: name, textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 14),
                TextField(controller: password, obscureText: hidePassword, onSubmitted: (_) => submit(),
                  decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => hidePassword = !hidePassword)))),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(error!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(registering ? 'Create account' : 'Log in', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton(onPressed: () => setState(() { registering = !registering; error = null; }),
                  child: Text(registering ? 'Already have an account? Log in' : 'New to CrazeChat? Create account')),
                const SizedBox(height: 12),
                Text('Local profile login only — not Firebase Authentication.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: dark ? Colors.white54 : muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.uid, required this.username, required this.onLogout, required this.onTheme});
  final String uid, username;
  final Future<void> Function() onLogout;
  final Future<void> Function(bool) onTheme;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final userIdInput = TextEditingController();
  bool adding = false;

  @override
  void dispose() { userIdInput.dispose(); super.dispose(); }

  Future<void> startChat() async {
    final peerId = userIdInput.text.trim();
    if (peerId.isEmpty || peerId == widget.uid) return;
    try {
      final userSnap = await db.child('users/' + peerId).get();
      if (!userSnap.exists) throw Exception('User ID not found. Ask them to share their exact ID.');
      final data = Map<String, dynamic>.from(userSnap.value as Map);
      final ids = [widget.uid, peerId]..sort();
      final chatId = ids.join('_');
      await db.child('chats/' + chatId).update({
        'chatId': chatId,
        'members': {widget.uid: true, peerId: true},
        'createdAt': ServerValue.timestamp,
        'isGroup': false,
      });
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(
        uid: widget.uid, username: widget.username, chatId: chatId,
        title: (data['username'] ?? 'CrazeChat user').toString(), peerId: peerId,
      )));
      userIdInput.clear();
      setState(() => adding = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void showProfile() {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Your profile'),
      content: SelectableText('Username: ' + widget.username + '\nUser ID: ' + widget.uid),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        TextButton(onPressed: () {
          Clipboard.setData(ClipboardData(text: widget.uid));
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID copied')));
        }, child: const Text('Copy ID')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.forum_rounded, color: Colors.white, size: 19)),
          const SizedBox(width: 10),
          const Text('CrazeChat', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.6)),
        ]),
        actions: [
          IconButton(tooltip: 'My profile', onPressed: showProfile, icon: const Icon(Icons.account_circle_outlined)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'theme') await widget.onTheme(!dark);
              if (v == 'logout') await widget.onLogout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'theme', child: Text(dark ? 'Use system theme' : 'Dark theme')),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (adding) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: Row(children: [
          Expanded(child: TextField(controller: userIdInput, decoration: const InputDecoration(
            hintText: 'Enter exact user ID', prefixIcon: Icon(Icons.search)), onSubmitted: (_) => startChat())),
          const SizedBox(width: 8),
          FilledButton(onPressed: startChat, child: const Text('Chat')),
        ])),
        const Padding(padding: EdgeInsets.fromLTRB(18, 12, 18, 16), child: Align(alignment: Alignment.centerLeft,
          child: Text('MESSAGES', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)))),
        Expanded(child: StreamBuilder<DatabaseEvent>(
          stream: db.child('chats').onValue,
          builder: (context, snap) {
            if (snap.hasError) return emptyState('Database unavailable', Icons.cloud_off_outlined);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final raw = snap.data!.snapshot.value;
            if (raw is! Map) return emptyState('Your conversations will appear here.', Icons.forum_outlined);
            final chats = raw.entries.where((e) {
              if (e.value is! Map) return false;
              final members = (e.value as Map)['members'];
              return members is Map && members[widget.uid] == true;
            }).toList();
            if (chats.isEmpty) return emptyState('No conversations yet.\nStart a chat with a CrazeChat user ID.', Icons.chat_bubble_outline_rounded);
            chats.sort((a, b) {
              final ad = a.value as Map, bd = b.value as Map;
              return ((bd['updatedAt'] as num?) ?? 0).compareTo((ad['updatedAt'] as num?) ?? 0);
            });
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chats.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
              itemBuilder: (context, i) {
                final entry = chats[i];
                final data = Map<String, dynamic>.from(entry.value as Map);
                final members = (data['members'] as Map?)?.keys.map((e) => e.toString()).toList() ?? <String>[];
                final peer = members.firstWhere((m) => m != widget.uid, orElse: () => '');
                final label = (data['groupName'] ?? data['title'] ?? (peer.isEmpty ? 'Conversation' : peer)).toString();
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  leading: CircleAvatar(radius: 26, backgroundColor: const Color(0xFFEFF6FF),
                    child: Icon(data['isGroup'] == true ? Icons.groups_rounded : Icons.person_rounded, color: blue)),
                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(data['lastMessage']?.toString() ?? 'Tap to open conversation', maxLines: 1,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: muted),
                  onTap: () async {
                    var title = label;
                    if (peer.isNotEmpty && data['isGroup'] != true) {
                      try {
                        final p = await db.child('users/' + peer + '/username').get();
                        if (p.exists) title = p.value.toString();
                      } catch (_) {}
                    }
                    if (!context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(
                      uid: widget.uid, username: widget.username, chatId: entry.key.toString(), title: title, peerId: peer,
                    )));
                  },
                );
              },
            );
          },
        )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => adding = !adding),
        icon: const Icon(Icons.edit_square_rounded), label: const Text('New chat'),
      ),
    );
  }
}

Widget emptyState(String message, IconData icon) => Center(
  child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 44, color: muted), const SizedBox(height: 14),
    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.5)),
  ])),
);

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, required this.uid, required this.username, required this.chatId, required this.title, required this.peerId});
  final String uid, username, chatId, title, peerId;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final message = TextEditingController();
  bool sending = false;

  @override
  void dispose() { message.dispose(); super.dispose(); }

  Future<void> send() async {
    final text = message.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final ref = db.child('chats/' + widget.chatId + '/messages').push();
      await ref.set({
        'senderId': widget.uid,
        'receiverId': widget.peerId,
        'senderUsername': widget.username,
        'ciphertext': text,
        'nonce': '',
        'timestamp': ServerValue.timestamp,
        'isEdited': false,
        'isPinned': false,
        'isDeleted': false,
      });
      await db.child('chats/' + widget.chatId).update({
        'updatedAt': ServerValue.timestamp,
        'lastMessage': text,
      });
      message.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: ' + e.toString())));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
      title: Row(children: [
        CircleAvatar(backgroundColor: const Color(0xFFEFF6FF),
          child: Icon(widget.peerId.isEmpty ? Icons.groups_rounded : Icons.person_rounded, color: blue)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const Text('CrazeChat', style: TextStyle(fontSize: 12, color: muted)),
        ])),
      ]),
    ),
    body: Column(children: [
      Expanded(child: StreamBuilder<DatabaseEvent>(
        stream: db.child('chats/' + widget.chatId + '/messages').orderByChild('timestamp').onValue,
        builder: (context, snap) {
          if (snap.hasError) return emptyState('Unable to load messages.', Icons.cloud_off_outlined);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final raw = snap.data!.snapshot.value;
          if (raw is! Map) return emptyState('Say hello 👋', Icons.waving_hand_outlined);
          final entries = raw.entries.toList()..sort((a, b) {
            final av = (a.value as Map?)?['timestamp'] as num? ?? 0;
            final bv = (b.value as Map?)?['timestamp'] as num? ?? 0;
            return av.compareTo(bv);
          });
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final item = Map<String, dynamic>.from(entries[i].value as Map);
              if (item['isDeleted'] == true) return const SizedBox.shrink();
              final mine = item['senderId'] == widget.uid;
              final timestamp = DateTime.fromMillisecondsSinceEpoch((item['timestamp'] as num?)?.toInt() ?? 0);
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: mine ? blue : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(mine ? 18 : 5), bottomRight: Radius.circular(mine ? 5 : 18),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Align(alignment: Alignment.centerLeft,
                      child: Text(item['ciphertext']?.toString() ?? '',
                        style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface, height: 1.35))),
                    const SizedBox(height: 4),
                    Text(DateFormat('HH:mm').format(timestamp),
                      style: TextStyle(color: mine ? Colors.white70 : muted, fontSize: 10)),
                  ]),
                ),
              );
            },
          );
        },
      )),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(controller: message, minLines: 1, maxLines: 5,
            textCapitalization: TextCapitalization.sentences, onSubmitted: (_) => send(),
            decoration: const InputDecoration(hintText: 'Message…', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),
          const SizedBox(width: 8),
          SizedBox(height: 52, width: 52, child: FilledButton(
            onPressed: sending ? null : send,
            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.arrow_upward_rounded),
          )),
        ]),
      )),
    ]),
  );
}
