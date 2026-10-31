import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'crypto_service.dart';
import 'session.dart';

const _brand = Color(0xFF087E65);
const _ink = Color(0xFF142A27);
const _canvas = Color(0xFFF3F7F5);
const _muted = Color(0xFF71817C);

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
  Widget build(BuildContext context) => MaterialApp(
    title: 'CrazeChat',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _brand, surface: Colors.white),
      scaffoldBackgroundColor: _canvas,
      appBarTheme: const AppBarTheme(backgroundColor: _canvas, surfaceTintColor: _canvas, elevation: 0, foregroundColor: _ink),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFFEAF1ED),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: _brand, width: 1.2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _brand, brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF0B1513),
      cardTheme: CardThemeData(color: const Color(0xFF14211E), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
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

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: _ink),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [_brand, Color(0xFF0B5147)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(Icons.bolt_rounded, color: Colors.white, size: size * .64),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
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
    } on ApiException catch (error) {
      if (mounted) { showMessage(context, error.message); }
    } catch (_) {
      if (mounted) {
        showMessage(context, creating
            ? 'Account setup failed. Check the API deployment and try again.'
            : 'Password could not unlock this account.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _BrandMark(size: 64),
            const SizedBox(height: 28),
            const _Eyebrow('CrazeStudio · Private network'),
            const SizedBox(height: 8),
            Text('Conversations,\nwithout the noise.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: colors.onSurface, fontWeight: FontWeight.w900, height: 1.04, letterSpacing: -1.4,
              )),
            const SizedBox(height: 12),
            Text('A quieter place to talk. Your messages are encrypted on this device before they leave it.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant, height: 1.45)),
            const SizedBox(height: 30),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Sign in'), icon: Icon(Icons.login_rounded)),
                ButtonSegment(value: true, label: Text('Create account'), icon: Icon(Icons.person_add_alt_1_rounded)),
              ],
              selected: {creating},
              onSelectionChanged: busy ? null : (value) => setState(() => creating = value.first),
            ),
            const SizedBox(height: 20),
            TextField(controller: username, autocorrect: false, textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email_rounded))),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: !showPassword,
              decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(onPressed: () => setState(() => showPassword = !showPassword),
                  icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility))),
              onSubmitted: (_) => submit()),
            if (creating) ...[
              const SizedBox(height: 10),
              Text('Use 12 or more characters. This password protects your private encryption key. Keep it safe.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(backgroundColor: _brand, padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(creating ? 'Create secure account' : 'Unlock and sign in'),
            ),
            const SizedBox(height: 22),
            const _SecurityNote(),
          ]),
        ),
      ))),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();
  @override
  Widget build(BuildContext context) => const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(Icons.verified_user_outlined, color: _brand, size: 20),
    SizedBox(width: 10),
    Expanded(child: Text(
      'Messages are encrypted on your device. The authenticated API stores encrypted envelopes, not readable message text.',
      style: TextStyle(fontSize: 12),
    )),
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
    if (password.text.isEmpty || busy) return;
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
          const Center(child: _BrandMark(size: 68)),
          const SizedBox(height: 22),
          Text('Welcome back, @${widget.session.username!}', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Unlock your private identity key on this device to open your conversations.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(controller: password, obscureText: !visible, onSubmitted: (_) => unlock(),
            decoration: InputDecoration(labelText: 'Account password', prefixIcon: const Icon(Icons.key_rounded),
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
  final search = TextEditingController();
  List<Map<String, dynamic>> chats = [];
  bool loading = true, failed = false;
  int page = 0;

  @override
  void initState() {
    super.initState();
    search.addListener(_changed);
    loadChats();
  }
  @override
  void dispose() { search.removeListener(_changed); search.dispose(); super.dispose(); }
  void _changed() => setState(() {});

  Future<void> loadChats() async {
    try {
      final data = await widget.session.api.get('/chats');
      final list = (data['chats'] as List? ?? const []).whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value)).toList();
      if (mounted) setState(() { chats = list; loading = false; failed = false; });
    } catch (error) {
      if (mounted) {
        setState(() { loading = false; failed = true; });
        showMessage(context, error.toString());
      }
    }
  }

  Future<void> startChat() async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Find a person'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(labelText: 'CrazeChat username', prefixIcon: Icon(Icons.alternate_email_rounded)),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Open conversation')),
        ],
      ),
    );
    controller.dispose();
    if (target == null || target.isEmpty || !mounted) return;
    try {
      final response = await widget.session.api.post('/chats', {'username': target});
      await openChat(Map<String, dynamic>.from(response['chat'] as Map));
    } catch (error) { if (mounted) showMessage(context, error.toString()); }
  }

  Future<void> openChat(Map<String, dynamic> chat) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(session: widget.session, chat: chat)));
    if (mounted) loadChats();
  }

  Map<String, dynamic>? _peer(Map<String, dynamic> chat) {
    final members = (chat['members'] as List? ?? const []).whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value));
    for (final member in members) {
      if (member['id'] != widget.session.userId) return member;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = chats.where((chat) {
      final name = _peer(chat)?['username']?.toString().toLowerCase() ?? '';
      return name.contains(search.text.trim().toLowerCase());
    }).toList();
    return Scaffold(
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
          child: Row(children: [
            const _BrandMark(),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('crazechat', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
              _Eyebrow('A private space'),
            ])),
            IconButton(tooltip: 'New conversation', onPressed: startChat, icon: const Icon(Icons.add_comment_outlined)),
            IconButton(tooltip: 'Account', onPressed: () => setState(() => page = 2), icon: const Icon(Icons.account_circle_outlined)),
          ]),
        ),
        Expanded(child: switch (page) {
          0 => _buildInbox(context, colors, filtered),
          1 => CloudPurgeDashboard(session: widget.session),
          _ => _buildSettings(context),
        }),
      ])),
      floatingActionButton: page == 0 ? FloatingActionButton(
        onPressed: startChat, backgroundColor: _brand, foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) => setState(() => page = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox_rounded), label: 'Inbox'),
          NavigationDestination(icon: Icon(Icons.cloud_sync_outlined), selectedIcon: Icon(Icons.cloud_sync_rounded), label: 'CloudPurge'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildInbox(BuildContext context, ColorScheme colors, List<Map<String, dynamic>> filtered) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Eyebrow('Your conversations'),
          const SizedBox(height: 5),
          Text('Talk freely.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900, letterSpacing: -1.2, color: _ink,
          )),
          const SizedBox(height: 14),
          TextField(controller: search, decoration: InputDecoration(
            hintText: 'Search conversations', prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: () => search.clear(), icon: const Icon(Icons.close_rounded)),
          )),
        ]),
      ),
      Expanded(child: RefreshIndicator(
        onRefresh: loadChats,
        child: loading ? const Center(child: CircularProgressIndicator())
          : failed && chats.isEmpty ? ListView(children: [
              const SizedBox(height: 100),
              const Icon(Icons.cloud_off_outlined, size: 52, color: _muted),
              const SizedBox(height: 12),
              const Center(child: Text('Could not load your inbox')),
              Center(child: TextButton.icon(onPressed: loadChats, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again'))),
            ])
          : filtered.isEmpty ? ListView(children: [
              const SizedBox(height: 72),
              Icon(Icons.forum_outlined, size: 58, color: colors.primary.withValues(alpha: .6)),
              const SizedBox(height: 16),
              Center(child: Text(search.text.isEmpty ? 'A fresh start.' : 'No matching conversations.',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(height: 7),
              Center(child: Text(search.text.isEmpty
                  ? 'Find someone on CrazeChat and start talking.'
                  : 'Try another username.', style: TextStyle(color: colors.onSurfaceVariant))),
              if (search.text.isEmpty) ...[
                const SizedBox(height: 18),
                Center(child: FilledButton.icon(onPressed: startChat,
                  icon: const Icon(Icons.person_search_rounded), label: const Text('Find someone'))),
              ],
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final chat = filtered[index];
                final name = _peer(chat)?['username']?.toString() ?? 'Unknown user';
                final initial = name.isEmpty ? '?' : name[0].toUpperCase();
                return Material(
                  color: Colors.white, borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => openChat(chat),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(color: const Color(0xFFE1F1E9), borderRadius: BorderRadius.circular(16)),
                          child: Center(child: Text(initial,
                            style: const TextStyle(color: _brand, fontSize: 18, fontWeight: FontWeight.w900))),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 4),
                          const Row(children: [
                            Icon(Icons.lock_outline_rounded, size: 13, color: _brand),
                            SizedBox(width: 5),
                            Text('Private conversation', style: TextStyle(color: _muted, fontSize: 12)),
                          ]),
                        ])),
                        const Icon(Icons.arrow_outward_rounded, color: _muted, size: 18),
                      ]),
                    ),
                  ),
                );
              },
            ),
      )),
    ]);
  }

  Widget _buildSettings(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
    children: [
      const _Eyebrow('Your account'),
      const SizedBox(height: 8),
      Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
      const SizedBox(height: 18),
      Card(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          const _BrandMark(size: 50),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@${widget.session.username}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            const Text('End-to-end encrypted account', style: TextStyle(color: _muted, fontSize: 12)),
          ])),
        ]),
      )),
      const SizedBox(height: 14),
      _SettingsAction(icon: Icons.cloud_sync_outlined, title: 'CloudPurge',
        subtitle: 'Receipt-based server cleanup', onTap: () => setState(() => page = 1)),
      _SettingsAction(icon: Icons.lock_outline_rounded, title: 'Lock CrazeChat',
        subtitle: 'Lock the local encryption identity', onTap: widget.session.lock),
      _SettingsAction(icon: Icons.switch_account_outlined, title: 'Switch account',
        subtitle: 'Manage saved accounts', onTap: _showAccounts),
      _SettingsAction(icon: Icons.person_add_alt_1_outlined, title: 'Add account',
        subtitle: 'Sign in with another CrazeChat account', onTap: widget.session.addAccount),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.session.signOut,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF9B3D35),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      const SizedBox(height: 20),
      const _SecurityNote(),
    ],
  );

  Future<void> _showAccounts() async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saved accounts', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...widget.session.savedAccounts.where((account) => account['userId'] != widget.session.userId).map((account) =>
            ListTile(leading: const Icon(Icons.account_circle_outlined), title: Text('@${account['username']}'),
              subtitle: const Text('Switch account'), onTap: () {
                Navigator.pop(sheetContext);
                widget.session.switchAccount(account['userId'] as String);
              })),
          if (!widget.session.savedAccounts.any((account) => account['userId'] != widget.session.userId))
            const ListTile(leading: Icon(Icons.info_outline), title: Text('No other account saved')),
        ]),
      )),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 5),
    leading: Container(width: 42, height: 42,
      decoration: BoxDecoration(color: const Color(0xFFE7F2EC), borderRadius: BorderRadius.circular(13)),
      child: Icon(icon, color: _brand)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  ));
}

class CloudPurgeDashboard extends StatefulWidget {
  const CloudPurgeDashboard({super.key, required this.session});
  final ChatSession session;
  @override
  State<CloudPurgeDashboard> createState() => _CloudPurgeDashboardState();
}
class _CloudPurgeDashboardState extends State<CloudPurgeDashboard> {
  int cachedMessages = 0;
  bool loading = true;
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final count = await widget.session.getCachedMessageCount();
      if (mounted) setState(() { cachedMessages = count; loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      children: [
        const _Eyebrow('Automatic message lifecycle'),
        const SizedBox(height: 6),
        Text('CloudPurge', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 8),
        const Text('Messages leave the server only after the receiver has decrypted the content and saved its encrypted envelope on their device.',
          style: TextStyle(color: _muted, height: 1.45)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0C7864), Color(0xFF124A43)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.cloud_done_outlined, color: Colors.white, size: 25),
              SizedBox(width: 9),
              Text('CLOUDPURGE PROTOCOL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
            const SizedBox(height: 16),
            Text(loading ? '—' : '$cachedMessages',
              style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
            const Text('encrypted message copies saved on this device', style: TextStyle(color: Color(0xFFD4E9E0))),
            const SizedBox(height: 18),
            const Divider(color: Color(0x55FFFFFF)),
            const Row(children: [
              Icon(Icons.verified_rounded, color: Color(0xFFB7E9D0), size: 17),
              SizedBox(width: 7),
              Expanded(child: Text('Local encrypted cache stays available after server cleanup.',
                style: TextStyle(color: Colors.white, fontSize: 12))),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        const _PurgeStep(number: '01', title: 'Receive',
          description: 'The receiver downloads the encrypted message from the authenticated API.'),
        const _PurgeStep(number: '02', title: 'Verify and save',
          description: 'The app decrypts the message and saves its encrypted envelope to secure local storage.'),
        const _PurgeStep(number: '03', title: 'Acknowledge',
          description: 'Only after the local save succeeds does the receiver send an authenticated receipt.'),
        const _PurgeStep(number: '04', title: 'Purge',
          description: 'The server writes a receipt tombstone and removes the server-side ciphertext atomically.'),
        const SizedBox(height: 12),
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: _brand),
            SizedBox(width: 10),
            Expanded(child: Text(
              'CloudPurge cannot independently inspect another device’s storage. It trusts the authenticated receiver app to acknowledge only after its local save completes.',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.45),
            )),
          ]),
        )),
      ],
    ),
  );
}

class _PurgeStep extends StatelessWidget {
  const _PurgeStep({required this.number, required this.title, required this.description});
  final String number;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(number, style: const TextStyle(color: _brand, fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
        ])),
      ]),
    )),
  );
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
  final search = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  final Set<String> messageIds = <String>{};
  final Set<String> purgeIds = <String>{};
  SecretKey? chatKey;
  String? peerName, error;
  bool loading = true, sending = false, syncing = false, searchOpen = false;
  int? lastMessageAt, lastPurgeAt;
  Timer? poller;

  String get chatId => widget.chat['id'] as String;
  Map<String, dynamic>? get peer {
    final members = (widget.chat['members'] as List? ?? const []).whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value));
    for (final member in members) {
      if (member['id'] != widget.session.userId) return member;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    search.addListener(_searchChanged);
    prepare();
  }
  @override
  void dispose() {
    poller?.cancel();
    input.dispose();
    search.removeListener(_searchChanged);
    search.dispose();
    scroll.dispose();
    super.dispose();
  }
  void _searchChanged() => setState(() {});

  Future<void> prepare() async {
    final other = peer;
    if (other == null || widget.session.identity == null) {
      if (mounted) setState(() { error = 'This conversation is missing an encryption identity.'; loading = false; });
      return;
    }
    peerName = other['username']?.toString() ?? 'Conversation';
    try {
      chatKey = await CryptoService.deriveChatKey(
        myKeyPair: widget.session.identity!,
        peerPublicKey: other['publicKey'] as String,
        chatId: chatId,
      );
      final cached = await widget.session.loadCachedMessages(chatId);
      for (final message in cached) {
        await _addLocalMessage(message);
      }
      if (mounted) setState(() => loading = false);
      await loadMessages();
      poller = Timer.periodic(const Duration(seconds: 4), (_) => loadMessages(silent: true));
    } catch (exception) {
      if (mounted) setState(() { error = 'Could not establish the encrypted conversation: $exception'; loading = false; });
    }
  }

  Future<Map<String, dynamic>> _decodeMessage(Map<String, dynamic> message) async {
    final clear = await CryptoService.decryptMessage(message: message, chatKey: chatKey!, chatId: chatId);
    return {...message, 'clearText': clear};
  }

  Future<void> _addLocalMessage(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || messageIds.contains(id)) return;
    try {
      final decoded = await _decodeMessage(message);
      messageIds.add(id);
      final timestamp = (decoded['createdAt'] as num?)?.toInt() ?? 0;
      if (lastMessageAt == null || timestamp > lastMessageAt!) lastMessageAt = timestamp;
      if (mounted) {
        setState(() {
          messages.add(decoded);
          messages.sort((a, b) => _time(a).compareTo(_time(b)));
        });
      }
    } catch (_) {
      // A damaged cache entry can be recovered from remote sync if it remains.
    }
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (chatKey == null || syncing) return;
    syncing = true;
    try {
      await _retryPendingMessages();
      final messageResponse = await widget.session.api.getMessages(
        chatId,
        since: lastMessageAt == null ? null : lastMessageAt! - 1,
        limit: 100,
      );
      final purges = await widget.session.api.getPurgedMessages(
        chatId,
        since: lastPurgeAt == null ? null : lastPurgeAt! - 1,
      );
      final raw = (messageResponse['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();

      for (final message in raw) {
        final id = message['id']?.toString();
        if (id == null) continue;
        final mine = message['senderId'] == widget.session.userId;
        try {
          // Decrypt first, then persist the encrypted envelope. The receiver's
          // authenticated receipt is sent only after this local save succeeds.
          final decoded = await _decodeMessage(message);
          await widget.session.saveCachedMessage(chatId, {
            ...message,
            'deliveryState': mine ? 'sent' : 'saved',
          });
          if (!mine) {
            await widget.session.api.acknowledgeMessage(chatId, id);
            await widget.session.updateCachedMessage(chatId, id, deliveryState: 'cloudpurged');
            decoded['deliveryState'] = 'cloudpurged';
          }
          final timestamp = (message['createdAt'] as num?)?.toInt() ?? 0;
          if (lastMessageAt == null || timestamp > lastMessageAt!) lastMessageAt = timestamp;
          if (!messageIds.contains(id)) {
            messageIds.add(id);
            messages.add(decoded);
          } else {
            final index = messages.indexWhere((item) => item['id'] == id);
            if (index >= 0) messages[index] = decoded;
          }
        } catch (exception) {
          if (!silent && mounted) showMessage(context, 'Message $id was not acknowledged: $exception');
        }
      }

      for (final purge in purges) {
        final id = purge['messageId']?.toString();
        if (id == null) continue;
        final purgedAt = (purge['purgedAt'] as num?)?.toInt() ?? 0;
        if (lastPurgeAt == null || purgedAt > lastPurgeAt!) lastPurgeAt = purgedAt;
        if (!purgeIds.add(id)) continue;
        if (purge['reason'] == 'sender-delete') {
          await widget.session.deleteCachedMessage(chatId, id);
          messages.removeWhere((item) => item['id'] == id);
          messageIds.remove(id);
        } else if (purge['reason'] == 'cloudpurge-received' &&
            purge['senderId'] == widget.session.userId) {
          await widget.session.updateCachedMessage(chatId, id, deliveryState: 'cloudpurged');
          final index = messages.indexWhere((item) => item['id'] == id);
          if (index >= 0) messages[index]['deliveryState'] = 'cloudpurged';
        }
      }

      messages.sort((a, b) => _time(a).compareTo(_time(b)));
      if (mounted) setState(() { loading = false; error = null; });
      if (!silent) _scrollToBottom();
    } catch (exception) {
      if (mounted && !silent) setState(() { error = exception.toString(); loading = false; });
    } finally {
      syncing = false;
    }
  }

  Future<void> _retryPendingMessages() async {
    final cached = await widget.session.loadCachedMessages(chatId);
    for (final item in cached) {
      if (item['senderId'] != widget.session.userId || item['deliveryState'] != 'queued') continue;
      final id = item['id']?.toString();
      if (id == null) continue;
      try {
        final response = await widget.session.api.post('/chats/$chatId/messages', {
          'id': id, 'format': item['format'], 'ciphertext': item['ciphertext'],
          'nonce': item['nonce'], 'mac': item['mac'],
        });
        final serverMessage = Map<String, dynamic>.from(response['message'] as Map);
        await widget.session.updateCachedMessage(chatId, id,
          deliveryState: 'sent', serverMessage: serverMessage);
      } on ApiException catch (exception) {
        if (exception.statusCode != null && exception.statusCode! >= 400 &&
            exception.statusCode! < 500 && exception.statusCode != 429 && mounted) {
          showMessage(context, 'A queued message needs attention: ${exception.message}');
        }
      }
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending || chatKey == null) return;
    setState(() => sending = true);
    input.clear();
    final id = widget.session.api.createMessageId();
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final encrypted = await CryptoService.encryptMessage(
        text: text, chatKey: chatKey!, chatId: chatId, senderId: widget.session.userId!,
      );
      final queued = <String, dynamic>{
        'id': id, 'senderId': widget.session.userId, ...encrypted,
        'createdAt': createdAt, 'deliveryState': 'queued',
      };
      // Sender cache is durable before the server makes the message visible,
      // preventing a fast receiver acknowledgement from racing the sender save.
      await widget.session.saveCachedMessage(chatId, queued);
      if (mounted) {
        setState(() {
          messages.add({...queued, 'clearText': text});
        messageIds.add(id);
          lastMessageAt = createdAt;
        });
      }
      _scrollToBottom();
      try {
        final response = await widget.session.api.post('/chats/$chatId/messages', {
          'id': id, 'format': encrypted['format'], 'ciphertext': encrypted['ciphertext'],
          'nonce': encrypted['nonce'], 'mac': encrypted['mac'],
        });
        final serverMessage = Map<String, dynamic>.from(response['message'] as Map);
        await widget.session.updateCachedMessage(chatId, id,
          deliveryState: 'sent', serverMessage: serverMessage);
        if (mounted) {
          final index = messages.indexWhere((item) => item['id'] == id);
          if (index >= 0) setState(() => messages[index]['deliveryState'] = 'sent');
        }
      } catch (_) {
        if (mounted) showMessage(context, 'Saved to your outbox. CrazeChat will retry when the connection returns.');
      }
    } catch (exception) {
      input.text = text;
      if (mounted) showMessage(context, exception.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text('The server copy will be removed and a deletion receipt will synchronize to the other participant.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep message')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF9B3D35)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session.api.delete('/chats/$chatId/messages/$id');
      await widget.session.deleteCachedMessage(chatId, id);
      if (!mounted) return;
      setState(() { messages.removeWhere((item) => item['id'] == id); messageIds.remove(id); });
      showMessage(context, 'Message deleted.');
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString());
    }
  }

  Future<void> messageActions(Map<String, dynamic> message) async {
    final mine = message['senderId'] == widget.session.userId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy message'),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: message['clearText']?.toString() ?? ''));
            if (sheetContext.mounted) Navigator.pop(sheetContext);
            if (mounted) showMessage(context, 'Message copied.');
          },
        ),
        if (mine) ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFF9B3D35)),
          title: const Text('Delete message'),
          onTap: () { Navigator.pop(sheetContext); deleteMessage(message); },
        ),
      ])),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  int _time(Map<String, dynamic> message) => (message['createdAt'] as num?)?.toInt() ?? 0;
  String _clock(Object? value) {
    final timestamp = value is num ? value.toInt() : 0;
    if (timestamp <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = messages.where((message) =>
      (message['clearText']?.toString().toLowerCase() ?? '').contains(search.text.trim().toLowerCase())
    ).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFFE1F1E9), borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(
              (peerName ?? '?').isEmpty ? '?' : peerName![0].toUpperCase(),
              style: const TextStyle(color: _brand, fontWeight: FontWeight.w900),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(peerName ?? 'Conversation', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Row(children: [
              Icon(Icons.shield_outlined, size: 12, color: _brand),
              SizedBox(width: 4),
              Text('Private channel', style: TextStyle(fontSize: 10, color: _muted)),
            ]),
          ])),
        ]),
        actions: [
          IconButton(
            tooltip: searchOpen ? 'Close search' : 'Search messages',
            onPressed: () => setState(() { searchOpen = !searchOpen; search.clear(); }),
            icon: Icon(searchOpen ? Icons.close_rounded : Icons.search_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFE5F2EB), borderRadius: BorderRadius.circular(14)),
          child: const Row(children: [
            Icon(Icons.auto_awesome_rounded, color: _brand, size: 17),
            SizedBox(width: 8),
            Expanded(child: Text(
              'CLOUDPURGE ACTIVE · Server copies clear after receiver save',
              style: TextStyle(color: Color(0xFF175C4B), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .3),
            )),
          ]),
        ),
        if (searchOpen) Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: TextField(controller: search, autofocus: true,
            decoration: const InputDecoration(hintText: 'Search in this conversation', prefixIcon: Icon(Icons.search_rounded))),
        ),
        if (error != null && !loading) Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Material(
            color: const Color(0xFFFFEDE9), borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_off_outlined, color: Color(0xFF9B3D35)),
              title: Text(error!, style: const TextStyle(fontSize: 12)),
              trailing: IconButton(onPressed: () => loadMessages(), icon: const Icon(Icons.refresh_rounded)),
            ),
          ),
        ),
        Expanded(
          child: loading ? const Center(child: CircularProgressIndicator())
            : error != null && messages.isEmpty ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_clock_outlined, size: 48, color: _muted),
                  const SizedBox(height: 12),
                  const Text('Conversation not synced'),
                  const SizedBox(height: 8),
                  FilledButton.icon(onPressed: () => loadMessages(), icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                ]),
              ))
            : visible.isEmpty ? Center(child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const _BrandMark(size: 52),
                  const SizedBox(height: 14),
                  Text(search.text.isEmpty ? 'This channel is yours.' : 'No matching messages.',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Encrypted before sending. Saved on your device.',
                    textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
                ]),
              ))
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final message = visible[index];
                  final mine = message['senderId'] == widget.session.userId;
                  final state = message['deliveryState']?.toString() ?? '';
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .84),
                      child: GestureDetector(
                        onLongPress: () => messageActions(message),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.fromLTRB(15, 13, 15, 11),
                          decoration: BoxDecoration(
                            color: mine ? const Color(0xFFE0F1E8) : Colors.white,
                            borderRadius: BorderRadius.circular(19),
                            border: Border.all(color: mine ? const Color(0xFFC6E4D4) : const Color(0xFFE5ECE8)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(mine ? 'YOU' : (peerName ?? 'CONTACT').toUpperCase(),
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _brand, letterSpacing: 1)),
                              const SizedBox(width: 9),
                              Text(_clock(message['createdAt']), style: const TextStyle(fontSize: 10, color: _muted)),
                            ]),
                            const SizedBox(height: 7),
                            Text(message['clearText']?.toString() ?? '',
                              style: const TextStyle(fontSize: 14, height: 1.4, color: _ink)),
                            if (mine && state.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  state == 'cloudpurged' ? Icons.cloud_done_rounded
                                      : state == 'queued' ? Icons.schedule_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 12, color: _brand,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  state == 'cloudpurged' ? 'CLOUDPURGE COMPLETE'
                                      : state == 'queued' ? 'WAITING TO SEND' : 'SENT · AWAITING RECEIPT',
                                  style: const TextStyle(fontSize: 9, color: _brand, fontWeight: FontWeight.w800, letterSpacing: .3),
                                ),
                              ]),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5ECE8)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(
                controller: input, minLines: 1, maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => send(),
                decoration: const InputDecoration(
                  hintText: 'Write something…',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  fillColor: _canvas,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              )),
              const SizedBox(width: 8),
              SizedBox(
                width: 48, height: 48,
                child: FilledButton(
                  onPressed: sending ? null : send,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero, backgroundColor: _brand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
