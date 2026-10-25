import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

const blue = Color(0xFF2563EB);
const muted = Color(0xFF64748B);
final db = FirebaseDatabase.instance.ref();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const CrazeChatApp());
}

class CrazeChatApp extends StatefulWidget {
  const CrazeChatApp({super.key});
  @override State<CrazeChatApp> createState() => _CrazeChatAppState();
}
class _CrazeChatAppState extends State<CrazeChatApp> {
  String? uid;
  String username = '';
  ThemeMode mode = ThemeMode.system;
  @override void initState() { super.initState(); restore(); }
  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() { uid = p.getString('uid'); username = p.getString('username') ?? ''; mode = p.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.system; });
  }
  Future<void> session(String id, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('uid', id); await p.setString('username', name);
    if (mounted) setState(() { uid = id; username = name; });
  }
  Future<void> logout() async {
    final p = await SharedPreferences.getInstance(); await p.remove('uid'); await p.remove('username');
    if (mounted) setState(() { uid = null; username = ''; });
  }
  Future<void> theme(bool dark) async {
    final p = await SharedPreferences.getInstance(); await p.setString('theme', dark ? 'dark' : 'system');
    if (mounted) setState(() => mode = dark ? ThemeMode.dark : ThemeMode.system);
  }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'CrazeChat', debugShowCheckedModeBanner: false, themeMode: mode,
    theme: appTheme(Brightness.light), darkTheme: appTheme(Brightness.dark),
    home: uid == null ? WelcomePage(onSession: session) : HomePage(uid: uid!, username: username, onLogout: logout, onTheme: theme),
  );
}
ThemeData appTheme(Brightness b) {
  final dark = b == Brightness.dark;
  return ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: b, surface: dark ? const Color(0xFF1E293B) : Colors.white),
    scaffoldBackgroundColor: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    appBarTheme: AppBarTheme(backgroundColor: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC), foregroundColor: dark ? Colors.white : const Color(0xFF0F172A), elevation: 0),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: dark ? const Color(0xFF1E293B) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: dark ? Colors.white12 : const Color(0xFFE2E8F0)))));
}
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onSession});
  final Future<void> Function(String, String) onSession;
  @override State<WelcomePage> createState() => _WelcomePageState();
}
class _WelcomePageState extends State<WelcomePage> {
  final name = TextEditingController(), pass = TextEditingController();
  bool registering = true, busy = false, hide = true;
  String? error;
  String hash(String s) => sha256.convert(utf8.encode('CrazeChat_Salt_2026_$s')).toString();
  @override void dispose() { name.dispose(); pass.dispose(); super.dispose(); }
  Future<void> submit() async {
    final n = name.text.trim(), p = pass.text;
    if (n.length < 3 || p.length < 6) { setState(() => error = 'Username must be 3+ characters and password 6+.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final prefs = await SharedPreferences.getInstance(); final key = 'profile_${n.toLowerCase()}'; final existing = prefs.getString(key);
      if (registering && existing != null) throw Exception('Username already exists on this device.');
      if (!registering && existing == null) throw Exception('No local profile found. Register on this device first.');
      if (registering) {
        final id = const Uuid().v4(); await prefs.setString(key, '$id|${hash(p)}');
        await db.child('users/$id').set({'userId': id, 'username': n, 'publicKey': '', 'pfpUrl': '', 'createdAt': ServerValue.timestamp});
        await widget.onSession(id, n);
      } else {
        final bits = existing!.split('|'); if (bits.length != 2 || bits[1] != hash(p)) throw Exception('Incorrect password.');
        await widget.onSession(bits[0], n);
      }
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(width: 76, height: 76, decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.forum_rounded, color: Colors.white, size: 38)),
      const SizedBox(height: 26), const Text('CrazeChat', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
      const SizedBox(height: 8), Text(registering ? 'A calmer space for your conversations.' : 'Welcome back.', style: const TextStyle(color: muted)),
      const SizedBox(height: 28), TextField(controller: name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 14), TextField(controller: pass, obscureText: hide, onSubmitted: (_) => submit(), decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => hide = !hide), icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 20), FilledButton(onPressed: busy ? null : submit, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: busy ? const CircularProgressIndicator() : Text(registering ? 'Create account' : 'Log in')),
      TextButton(onPressed: () => setState(() { registering = !registering; error = null; }), child: Text(registering ? 'Already have an account? Log in' : 'Create an account')),
      const Text('Local profile login only — not Firebase Authentication.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
    ]))))));
}
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.uid, required this.username, required this.onLogout, required this.onTheme});
  final String uid, username; final Future<void> Function() onLogout; final Future<void> Function(bool) onTheme;
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  final user = TextEditingController(); bool adding = false;
  @override void dispose() { user.dispose(); super.dispose(); }
  Future<void> startChat() async {
    final peer = user.text.trim(); if (peer.isEmpty || peer == widget.uid) return;
    try {
      final snap = await db.child('users/$peer').get(); if (!snap.exists) throw Exception('User ID not found.');
      final data = Map<String, dynamic>.from(snap.value as Map);
      final ids = [widget.uid, peer]..sort(); final id = 'chat_${ids[0]}_${ids[1]}';
      final members = {widget.uid: true, peer: true};
      await db.child('chats/$id').update({'chatId': id, 'members': members, 'participants': members, 'createdAt': ServerValue.timestamp, 'isGroup': false});
      for (final who in ids) { await db.child('users/$who/inbox/$id').set({'chatId': id, 'senderId': widget.uid, 'senderUsername': widget.username, 'timestamp': ServerValue.timestamp}); }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(uid: widget.uid, username: widget.username, chatId: id, peerId: peer, title: (data['username'] ?? peer).toString())));
      user.clear(); setState(() => adding = false);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }
  @override Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(appBar: AppBar(title: Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.forum_rounded, color: Colors.white, size: 19)), const SizedBox(width: 10), const Text('CrazeChat', style: TextStyle(fontWeight: FontWeight.w900))]),
      actions: [IconButton(onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Your profile'), content: SelectableText('Username: ${widget.username}\nUser ID: ${widget.uid}'), actions: [TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: widget.uid)); Navigator.pop(context); }, child: const Text('Copy ID'))])), icon: const Icon(Icons.account_circle_outlined)),
        PopupMenuButton<String>(onSelected: (v) async { if (v == 'theme') await widget.onTheme(!dark); if (v == 'logout') await widget.onLogout(); }, itemBuilder: (_) => [PopupMenuItem(value: 'theme', child: Text(dark ? 'System theme' : 'Dark theme')), const PopupMenuItem(value: 'logout', child: Text('Log out'))])],
      body: Column(children: [
        if (adding) Padding(padding: const EdgeInsets.all(14), child: Row(children: [Expanded(child: TextField(controller: user, decoration: const InputDecoration(hintText: 'Exact user ID'), onSubmitted: (_) => startChat())), const SizedBox(width: 8), FilledButton(onPressed: startChat, child: const Text('Chat'))])),
        const Padding(padding: EdgeInsets.fromLTRB(18, 14, 18, 14), child: Align(alignment: Alignment.centerLeft, child: Text('MESSAGES', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)))),
        Expanded(child: StreamBuilder<DatabaseEvent>(stream: db.child('chats').onValue, builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Database unavailable'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final raw = snap.data!.snapshot.value; if (raw is! Map) return const Center(child: Text('Start a conversation with a user ID.'));
          final chats = raw.entries.where((e) => e.value is Map && (e.value as Map)['members'] is Map && ((e.value as Map)['members'] as Map)[widget.uid] == true).toList();
          if (chats.isEmpty) return const Center(child: Text('No conversations yet.\nTap New chat to begin.', textAlign: TextAlign.center));
          chats.sort((a,b) => (((b.value as Map)['updatedAt'] as num?) ?? 0).compareTo((((a.value as Map)['updatedAt'] as num?) ?? 0)));
          return ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: chats.length, separatorBuilder: (_,__) => const Divider(height: 1, indent: 72), itemBuilder: (context, i) {
            final entry = chats[i]; final data = Map<String,dynamic>.from(entry.value as Map); final members = (data['members'] as Map).keys.map((x) => x.toString()).toList(); final peer = members.firstWhere((x) => x != widget.uid, orElse: () => '');
            final title = (data['groupName'] ?? data['title'] ?? peer).toString();
            return ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2), leading: CircleAvatar(backgroundColor: const Color(0xFFEFF6FF), child: Icon(data['isGroup'] == true ? Icons.groups_rounded : Icons.person_rounded, color: blue)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(data['lastMessage']?.toString() ?? 'Tap to open conversation', maxLines: 1, overflow: TextOverflow.ellipsis), trailing: const Icon(Icons.chevron_right_rounded, color: muted),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(uid: widget.uid, username: widget.username, chatId: entry.key.toString(), peerId: peer, title: title))));
          });
        })),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => setState(() => adding = !adding), icon: const Icon(Icons.edit_square_rounded), label: const Text('New chat')));
  }
}
class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, required this.uid, required this.username, required this.chatId, required this.peerId, required this.title});
  final String uid, username, chatId, peerId, title;
  @override State<ConversationPage> createState() => _ConversationPageState();
}
class _ConversationPageState extends State<ConversationPage> {
  final text = TextEditingController(); bool sending = false;
  @override void dispose() { text.dispose(); super.dispose(); }
  Future<void> send() async {
    final value = text.text.trim(); if (value.isEmpty || sending) return; setState(() => sending = true);
    try {
      final ref = db.child('chats/${widget.chatId}/messages').push();
      await ref.set({'senderId': widget.uid, 'receiverId': widget.peerId, 'senderUsername': widget.username, 'ciphertext': value, 'nonce': '', 'timestamp': ServerValue.timestamp, 'isEdited': false, 'isPinned': false, 'isDeleted': false});
      await db.child('chats/${widget.chatId}').update({'updatedAt': ServerValue.timestamp, 'lastMessage': value});
      if (widget.peerId.isNotEmpty) await db.child('users/${widget.peerId}/inbox/${widget.chatId}').set({'chatId': widget.chatId, 'senderId': widget.uid, 'senderUsername': widget.username, 'timestamp': ServerValue.timestamp});
      text.clear();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e'))); }
    finally { if (mounted) setState(() => sending = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Row(children: [const CircleAvatar(backgroundColor: Color(0xFFEFF6FF), child: Icon(Icons.person_rounded, color: blue)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const Text('CrazeChat', style: TextStyle(fontSize: 12, color: muted))]))])),
    body: Column(children: [
      Expanded(child: StreamBuilder<DatabaseEvent>(stream: db.child('chats/${widget.chatId}/messages').orderByChild('timestamp').onValue, builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('Unable to load messages'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final raw = snap.data!.snapshot.value; if (raw is! Map) return const Center(child: Text('Say hello 👋'));
        final entries = raw.entries.toList()..sort((a,b) => (((a.value as Map?)?['timestamp'] as num?) ?? 0).compareTo((((b.value as Map?)?['timestamp'] as num?) ?? 0)));
        return ListView.builder(padding: const EdgeInsets.all(14), itemCount: entries.length, itemBuilder: (context, i) {
          final m = Map<String,dynamic>.from(entries[i].value as Map); if (m['isDeleted'] == true) return const SizedBox.shrink();
          final mine = m['senderId'] == widget.uid; final time = DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as num?)?.toInt() ?? 0);
          return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: mine ? blue : Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 5), bottomRight: Radius.circular(mine ? 5 : 18))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Align(alignment: Alignment.centerLeft, child: Text(m['ciphertext']?.toString() ?? '', style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface, height: 1.35))), const SizedBox(height: 4), Text(DateFormat('HH:mm').format(time), style: TextStyle(color: mine ? Colors.white70 : muted, fontSize: 10))])));
        });
      })),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: TextField(controller: text, minLines: 1, maxLines: 5, textCapitalization: TextCapitalization.sentences, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Message…', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),
        const SizedBox(width: 8), SizedBox(height: 52, width: 52, child: FilledButton(onPressed: sending ? null : send, style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: sending ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.arrow_upward_rounded))),
      ]))),
    ]));
}
