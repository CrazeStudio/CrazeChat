import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'crypto_service.dart';
import 'session.dart';
import 'profile_photo.dart';
import 'push_notifications.dart';
import 'local_folder_sync.dart';
import 'security_prefs.dart';
import 'sound_effects.dart';

const _brand = Color(0xFF087E65);
const _ink = Color(0xFF142A27);
const _canvas = Color(0xFFF3F7F5);

class CrazeChatApp extends StatefulWidget {
  const CrazeChatApp({super.key});
  @override
  State<CrazeChatApp> createState() => _CrazeChatAppState();
}

class _CrazeChatAppState extends State<CrazeChatApp> {
  final session = ChatSession();
  @override
  void initState() {
    super.initState();
    session.addListener(_syncPushRegistration);
    unawaited(CrazeChatSoundEffects.initialize());
    unawaited(SecurityPrefs.applyStoredScreenSecure());
    session.restore();
  }

  void _syncPushRegistration() {
    if (mounted) setState(() {});
    if (session.signedIn) {
      unawaited(
        PushNotificationService.configure(
          session.api,
          userId: session.userId,
          enabled: session.notificationsEnabled,
          soundEnabled: session.soundEffectsEnabled,
          vibrationEnabled: session.vibrationEnabled,
        ),
      );
    }
  }

  @override
  void dispose() {
    session.removeListener(_syncPushRegistration);
    session.dispose();
    unawaited(CrazeChatSoundEffects.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CrazeChat',
    debugShowCheckedModeBanner: false,
    themeMode: session.themeMode,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _brand,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: _canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: _canvas,
        surfaceTintColor: _canvas,
        elevation: 0,
        foregroundColor: _ink,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEAF1ED),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _brand, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: _brand,
            brightness: Brightness.dark,
          ).copyWith(
            primary: const Color(0xFF62D6AE),
            onPrimary: const Color(0xFF06251D),
            surface: const Color(0xFF0B1513),
            surfaceContainer: const Color(0xFF14211E),
            surfaceContainerHighest: const Color(0xFF20312D),
            onSurface: const Color(0xFFF1F7F4),
            onSurfaceVariant: const Color(0xFFB5C6BF),
            outlineVariant: const Color(0xFF344841),
          ),
      scaffoldBackgroundColor: const Color(0xFF0B1513),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B1513),
        foregroundColor: Color(0xFFF1F7F4),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF1B2B27),
        hintStyle: TextStyle(color: Color(0xFF9AAEA5)),
        labelStyle: TextStyle(color: Color(0xFFB5C6BF)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: Color(0xFF62D6AE), width: 1.2),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF14211E),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
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
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void showMessage(BuildContext context, String message) {
  final colors = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: colors.onInverseSurface),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
      ),
    );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [_brand, Color(0xFF0B5147)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(Icons.bolt_rounded, color: Colors.white, size: size * .64),
  );
}

class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({
    required this.username,
    this.userId,
    this.photoUrl,
    this.size = 52,
  });
  final String username;
  final String? userId;
  final String? photoUrl;
  final double size;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  Future<Uint8List?>? _photo;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(covariant _ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.photoUrl != widget.photoUrl) {
      _loadPhoto();
    }
  }

  void _loadPhoto() {
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
    final normalized = widget.username.trim();
    final stableHash = normalized.codeUnits.fold<int>(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    final color = palette[stableHash % palette.length];
    final initial = normalized.isEmpty ? '?' : normalized.substring(0, 1).toUpperCase();
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) => CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: color,
        foregroundImage: snapshot.data == null ? null : MemoryImage(snapshot.data!),
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.size * .39,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    ),
  );
}

// Live strength hint shown while creating an account. The password also
// protects the private encryption key, so length matters more than symbols.
class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    var score = 0;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;
    if (RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      score++;
    }
    final tooShort = password.length < 12;
    const labels = ['Too short', 'Weak', 'Okay', 'Strong', 'Very strong'];
    final label = tooShort ? labels[0] : labels[score.clamp(1, 4)];
    final fraction = password.isEmpty ? 0.0 : (tooShort ? .15 : score / 4);
    final color = tooShort
        ? colors.error
        : score >= 3
        ? _brand
        : const Color(0xFFD9822B);
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              color: color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            password.isEmpty
                ? 'Use 12+ characters. This password also protects your encryption key.'
                : '$label \u00b7 12+ characters; a long passphrase works best.',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
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
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final name = username.text.trim();
    final pass = password.text;
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(name)) {
      showMessage(context, 'Username: 3\u201320 letters, numbers, or underscores.');
      return;
    }
    if (creating && pass.length < 12) {
      showMessage(context, 'Use a password with at least 12 characters.');
      return;
    }
    if (pass.isEmpty) {
      showMessage(context, 'Enter your account password.');
      return;
    }
    setState(() => busy = true);
    try {
      late final Map<String, dynamic> result;
      late final IdentityMaterial material;
      if (creating) {
        material = await CryptoService.createIdentity(pass);
        result = await widget.session.api.register(
          username: name,
          password: pass,
          identityEnvelope: material.envelope,
        );
      } else {
        result = await widget.session.api.login(username: name, password: pass);
        final envelope = Map<String, dynamic>.from(result['identityEnvelope'] as Map);
        final account = Map<String, dynamic>.from(result['user'] as Map);
        material = await widget.session.unlockForLogin(envelope: envelope, password: pass, accountId: account['id'] as String);
      }
      await widget.session.acceptSession(result, material);
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, error.message);
      }
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          creating
              ? 'Account setup failed. Check the API deployment and try again.'
              : 'Password could not unlock this account.',
        );
      }
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
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandMark(size: 64),
                  const SizedBox(height: 28),
                  const _Eyebrow('CrazeStudio \u00b7 Private network'),
                  const SizedBox(height: 8),
                  Text(
                    'Conversations,\nwithout the noise.',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w900,
                      height: 1.04,
                      letterSpacing: -1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A quieter place to talk. Your messages are encrypted on this device before they leave it.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 30),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Sign in'),
                        icon: Icon(Icons.login_rounded),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Create account'),
                        icon: Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ],
                    selected: {creating},
                    onSelectionChanged: busy
                        ? null
                        : (value) => setState(() => creating = value.first),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: username,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: !showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      creating
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Account password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: showPassword
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: () =>
                            setState(() => showPassword = !showPassword),
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  if (creating)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: password,
                      builder: (context, value, _) =>
                          _PasswordStrength(password: value.text),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            creating
                                ? 'Create secure account'
                                : 'Unlock and sign in',
                          ),
                  ),
                  const SizedBox(height: 22),
                  const _SecurityNote(),
                ],
              ),
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
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.verified_user_outlined, color: _brand, size: 20),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'Messages are encrypted on your device. The authenticated API stores encrypted envelopes, not readable message text.',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
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
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> unlock() async {
    if (password.text.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await widget.session.unlock(password.text);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Incorrect password or damaged encrypted key backup.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble(),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _BrandMark(size: 68)),
                    const SizedBox(height: 22),
                    Text(
                      'Welcome back, @${widget.session.username!}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Unlock your private identity key on this device to open your conversations.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: password,
                      obscureText: !visible,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => unlock(),
                      decoration: InputDecoration(
                        labelText: 'Account password',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          tooltip: visible ? 'Hide password' : 'Show password',
                          onPressed: () => setState(() => visible = !visible),
                          icon: Icon(
                            visible ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : unlock,
                      child: busy
                          ? const CircularProgressIndicator()
                          : const Text('Unlock CrazeChat'),
                    ),
                    TextButton(
                      onPressed: widget.session.signOut,
                      child: const Text('Sign in to another account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final ChatSession session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final search = TextEditingController();
  StreamSubscription<String>? pushOpenSubscription;
  List<Map<String, dynamic>> chats = [];
  bool loading = true, failed = false, syncingChats = false;
  bool refreshingChats = false;
  int page = 0;
  // Bumped after returning from a chat so each tile re-reads its contact's
  // key status (the user may have verified it inside the chat).
  int _tileEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    search.addListener(_changed);
    pushOpenSubscription = PushNotificationService.chatOpened.listen(
      _openNotificationChat,
    );
    final pendingChatId = PushNotificationService.consumePendingChatId();
    if (pendingChatId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openNotificationChat(pendingChatId),
      );
    }
    loadChats();
    unawaited(LocalFolderSyncService.instance.syncIfEnabled(widget.session));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pushOpenSubscription?.cancel();
    search.removeListener(_changed);
    search.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeFromBackground());
    }
  }

  Future<void> _resumeFromBackground() async {
    if (!mounted) return;
    loadChats(silent: true);
    unawaited(LocalFolderSyncService.instance.syncIfEnabled(widget.session));
  }

  Future<void> loadChats({bool silent = false}) async {
    if (syncingChats) return;
    syncingChats = true;
    if (mounted) setState(() => refreshingChats = true);
    try {
      // The inbox only needs the chat list from the server. It used to read
      // every chat's full local message history here to compute a count that
      // no screen displayed, which delayed the first paint.
      final data = await widget.session.api.listChats();
      final list = (data['chats'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      if (!mounted) return;
      final changed = jsonEncode(chats) != jsonEncode(list);
      if (changed || loading || failed) {
        setState(() {
          chats = list;
          loading = false;
          failed = false;
        });
      }
    } catch (error) {
      if (mounted && !silent) {
        setState(() {
          loading = false;
          failed = true;
        });
        if (chats.isEmpty) showMessage(context, error.toString());
      }
    } finally {
      syncingChats = false;
      if (mounted) setState(() => refreshingChats = false);
    }
  }

  Future<void> startChat() async {
    final target = await showDialog<String>(
      context: context,
      builder: (_) => _FindPeopleDialog(session: widget.session),
    );
    if (target == null || target.isEmpty || !mounted) return;
    try {
      final response = await widget.session.api.createChat(target);
      await openChat(Map<String, dynamic>.from(response['chat'] as Map));
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    }
  }

  Future<void> openChat(Map<String, dynamic> chat) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 230),
        reverseTransitionDuration: const Duration(milliseconds: 190),
        pageBuilder: (_, __, ___) =>
            ChatScreen(session: widget.session, chat: chat),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.035, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (mounted) {
      setState(() => _tileEpoch++);
      loadChats(silent: true);
    }
  }

  Future<void> _openNotificationChat(String chatId) async {
    await loadChats(silent: true);
    if (!mounted) return;
    for (final chat in chats) {
      if (chat['id']?.toString() == chatId) {
        await openChat(chat);
        return;
      }
    }
    showMessage(context, 'Open CrazeChat to sync this conversation.');
  }

  Map<String, dynamic>? _peer(Map<String, dynamic> chat) {
    final members = (chat['members'] as List? ?? const []).whereType<Map>().map(
      (value) => Map<String, dynamic>.from(value),
    );
    for (final member in members) {
      if (member['id'] != widget.session.userId) return member;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isInbox = page == 0;
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colors.surface,
      floatingActionButton: isInbox && !loading
          ? FloatingActionButton.extended(
              onPressed: startChat,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New chat'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) => setState(() => page = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                  child: Row(
                    children: [
                      const _BrandMark(size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'CrazeChat',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      if (refreshingChats)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Semantics(
                        button: true,
                        label: 'Open settings',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => page = 1),
                          child: _ProfileAvatar(
                            username: widget.session.username ?? 'user',
                            userId: widget.session.userId,
                            photoUrl: widget.session.photoUrl,
                            size: 36,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isInbox)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'Search chats',
                        prefixIcon: const Icon(Icons.search_rounded, size: 21),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: search.clear,
                                icon: const Icon(Icons.close_rounded, size: 20),
                              ),
                        filled: true,
                        fillColor: dark
                            ? const Color(0xFF252D33)
                            : const Color(0xFFE9EFEC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: const BorderSide(color: _brand, width: 1.2),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    reverseDuration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0.02, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<int>(page),
                      child: switch (page) {
                        0 => _buildInbox(
                            context,
                            chats.where((chat) {
                              final name = _peer(chat)?['username']
                                      ?.toString()
                                      .toLowerCase() ??
                                  '';
                              return name.contains(
                                search.text.trim().toLowerCase(),
                              );
                            }).toList(),
                          ),
                        _ => _buildSettings(context),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInbox(
    BuildContext context,
    List<Map<String, dynamic>> filtered,
  ) {
    final colors = Theme.of(context).colorScheme;
    final Widget content = loading
        ? const Center(child: CircularProgressIndicator(color: _brand))
        : failed && chats.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 110),
                  Icon(Icons.cloud_off_rounded,
                      size: 46, color: colors.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('Could not load your chats',
                        style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text('Your conversations could not be refreshed.',
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: FilledButton.icon(
                      onPressed: refreshingChats ? null : () => loadChats(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              )
            : filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 90),
                      Center(
                        child: Icon(Icons.forum_outlined,
                            size: 42, color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          search.text.isEmpty
                              ? 'Your chats start here'
                              : 'No conversations found',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Center(
                        child: Text(
                          search.text.isEmpty
                              ? 'Start a private conversation with someone.'
                              : 'Try another name, or find someone new.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: FilledButton.icon(
                          onPressed: startChat,
                          icon: Icon(
                            search.text.isEmpty
                                ? Icons.add_comment_outlined
                                : Icons.person_search_rounded,
                          ),
                          label: Text(
                            search.text.isEmpty
                                ? 'Start a chat'
                                : 'Find new people',
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final chat = filtered[index];
                      final peer = _peer(chat);
                      return _ChatTile(
                        key: ValueKey('${chat['id']}#$_tileEpoch'),
                        session: widget.session,
                        name: peer?['username']?.toString() ?? 'Unknown user',
                        peer: peer,
                        onTap: () => openChat(chat),
                      );
                    },
                  );
    // Pull down on the chat list to refresh it.
    return RefreshIndicator(
      color: _brand,
      onRefresh: () => loadChats(silent: true),
      child: content,
    );
  }

  Widget _buildSettings(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const _Eyebrow('Your account'),
        const SizedBox(height: 8),
        Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _ProfileAvatar(
                  username: widget.session.username ?? 'user',
                  userId: widget.session.userId,
                  photoUrl: widget.session.photoUrl,
                  size: 54,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${widget.session.username}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'End-to-end encrypted account',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.photo_camera_back_rounded),
            title: const Text('Change profile photo', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Use a direct HTTPS image URL'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showProfilePhotoDialog,
          ),
        ),
        const SizedBox(height: 14),
        const _Eyebrow('Security'),
        const SizedBox(height: 8),
        _SecurityCard(session: widget.session),
        const SizedBox(height: 8),
        Card(child: ListTile(
          leading: const Icon(Icons.password_rounded),
          title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Update sign-in password and protect your identity key'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _showChangePassword,
        )),
        const SizedBox(height: 14),
        _LocalFolderSyncCard(session: widget.session),
        const SizedBox(height: 14),
        const _Eyebrow('Experience'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Push notifications'),
                subtitle: Text(
                  PushNotificationService.isAvailable
                      ? 'Receive alerts when CrazeChat is in the background'
                      : 'Add this Android app to Firebase to enable background alerts',
                ),
                value: widget.session.notificationsEnabled,
                activeThumbColor: _brand,
                onChanged: PushNotificationService.isAvailable
                    ? (value) => widget.session.setNotificationsEnabled(value)
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('Sound effects'),
                subtitle: const Text(
                  'Play a short sound when messages arrive or send',
                ),
                value: widget.session.soundEffectsEnabled,
                activeThumbColor: _brand,
                onChanged: (value) =>
                    widget.session.setSoundEffectsEnabled(value),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_outlined),
                title: const Text('Vibration'),
                subtitle: const Text(
                  'Use light haptic feedback for message actions',
                ),
                value: widget.session.vibrationEnabled,
                activeThumbColor: _brand,
                onChanged: (value) => widget.session.setVibrationEnabled(value),
              ),

              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Appearance',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: {widget.session.themeMode},
                      onSelectionChanged: (values) =>
                          widget.session.setThemeMode(values.first),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsAction(
          icon: Icons.switch_account_outlined,
          title: 'Switch account',
          subtitle: 'Manage saved accounts',
          onTap: _showAccounts,
        ),
        _SettingsAction(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Add account',
          subtitle: 'Sign in with another CrazeChat account',
          onTap: widget.session.addAccount,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.session.signOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF9B3D35),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _SecurityNote(),
      ],
    );
  }

  Future<void> _showProfilePhotoDialog() async {
    final controller = TextEditingController(text: widget.session.photoUrl ?? '');
    bool busy = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Profile photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Paste a direct HTTPS image URL. CrazeChat stores the URL on the server and caches the image locally in encrypted storage.'),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'https://example.com/photo.jpg',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.session.photoUrl != null)
                TextButton(
                  onPressed: busy ? null : () async {
                    setDialogState(() => busy = true);
                    try {
                      final id = widget.session.userId;
                      await widget.session.updateProfilePhoto(null);
                      if (id != null) await ProfilePhotoCache.clear(id);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (mounted) showMessage(this.context, 'Profile photo removed.');
                    } catch (error) {
                      if (dialogContext.mounted) showMessage(dialogContext, 'Could not remove profile photo: $error');
                    } finally {
                      if (dialogContext.mounted) setDialogState(() => busy = false);
                    }
                  },
                  child: const Text('Remove'),
                ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : () async {
                  final value = controller.text.trim();
                  final id = widget.session.userId;
                  if (id == null) {
                    showMessage(dialogContext, 'Sign in before changing your profile photo.');
                    return;
                  }
                  if (!ProfilePhotoCache.isValidUrl(value)) {
                    showMessage(dialogContext, 'Enter a valid HTTPS image URL.');
                    return;
                  }
                  setDialogState(() => busy = true);
                  try {
                    final image = await ProfilePhotoCache.load(userId: id, url: value);
                    if (image == null) {
                      throw const FormatException('The URL did not return a supported image under 256 KB.');
                    }
                    await widget.session.updateProfilePhoto(value);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) showMessage(this.context, 'Profile photo updated.');
                  } catch (error) {
                    if (dialogContext.mounted) showMessage(dialogContext, 'Could not update profile photo: $error');
                  } finally {
                    if (dialogContext.mounted) setDialogState(() => busy = false);
                  }
                },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save photo'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showChangePassword() async {
    final current = TextEditingController(), next = TextEditingController(), confirm = TextEditingController();
    bool busy = false, showCurrent = false, showNext = false, showConfirm = false;
    try {
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Change password', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Your password also protects your private encryption key. CrazeChat updates both securely.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 18),
              TextField(controller: current, obscureText: !showCurrent, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Current password', suffixIcon: IconButton(onPressed: () => setSheetState(() => showCurrent = !showCurrent), icon: Icon(showCurrent ? Icons.visibility_off : Icons.visibility)))),
              const SizedBox(height: 12),
              TextField(controller: next, obscureText: !showNext, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'New password (12+ characters)', suffixIcon: IconButton(onPressed: () => setSheetState(() => showNext = !showNext), icon: Icon(showNext ? Icons.visibility_off : Icons.visibility)))),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: next,
                builder: (context, value, _) => _PasswordStrength(password: value.text),
              ),
              const SizedBox(height: 12),
              TextField(controller: confirm, obscureText: !showConfirm, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Confirm new password', suffixIcon: IconButton(onPressed: () => setSheetState(() => showConfirm = !showConfirm), icon: Icon(showConfirm ? Icons.visibility_off : Icons.visibility)))),
              const SizedBox(height: 18),
              FilledButton(onPressed: busy ? null : () async {
                if (current.text.isEmpty) { showMessage(sheetContext, 'Enter your current password.'); return; }
                if (next.text.length < 12) { showMessage(sheetContext, 'The new password must have at least 12 characters.'); return; }
                if (next.text != confirm.text) { showMessage(sheetContext, 'The new passwords do not match.'); return; }
                if (next.text == current.text) { showMessage(sheetContext, 'Choose a different password.'); return; }
                setSheetState(() => busy = true);
                try {
                  await widget.session.changePassword(currentPassword: current.text, newPassword: next.text);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) showMessage(this.context, 'Password updated successfully.');
                } on ApiException catch (error) {
                  if (sheetContext.mounted) showMessage(sheetContext, error.message);
                } catch (_) {
                  if (sheetContext.mounted) showMessage(sheetContext, 'Password update failed. Your existing password remains active.');
                } finally { if (sheetContext.mounted) setSheetState(() => busy = false); }
              }, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Update password')),
            ])),
          ),
        )),
      );
    } finally { current.dispose(); next.dispose(); confirm.dispose(); }
  }

  Future<void> _showAccounts() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saved accounts',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ...widget.session.savedAccounts
                  .where(
                    (account) => account['userId'] != widget.session.userId,
                  )
                  .map(
                    (account) => ListTile(
                      leading: _ProfileAvatar(
                        username: account['username']?.toString() ?? 'user',
                        userId: account['userId']?.toString(),
                        photoUrl: account['photoUrl']?.toString(),
                        size: 42,
                      ),
                      title: Text('@${account['username']}'),
                      subtitle: const Text('Switch account'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        widget.session.switchAccount(
                          account['userId'] as String,
                        );
                      },
                    ),
                  ),
              if (!widget.session.savedAccounts.any(
                (account) => account['userId'] != widget.session.userId,
              ))
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No other account saved'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// One row of the chat list. It reads this contact's key-verification status
// once, so the list shows at a glance which conversations are verified.
class _ChatTile extends StatefulWidget {
  const _ChatTile({
    super.key,
    required this.session,
    required this.name,
    required this.peer,
    required this.onTap,
  });
  final ChatSession session;
  final String name;
  final Map<String, dynamic>? peer;
  final VoidCallback onTap;

  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  String keyStatus = 'unverified';

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  Future<void> _loadStatus() async {
    final id = widget.peer?['id']?.toString();
    final key = widget.peer?['publicKey']?.toString();
    if (id == null || key == null || key.isEmpty) return;
    try {
      final status = await widget.session.contactKeyStatus(
        contactId: id,
        publicKey: key,
      );
      if (mounted && status != keyStatus) setState(() => keyStatus = status);
    } catch (_) {
      // Keep the neutral "unverified" presentation.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final verified = keyStatus == 'verified';
    final changed = keyStatus == 'changed';
    final badgeColor = verified
        ? colors.primary
        : changed
        ? colors.error
        : const Color(0xFFD9822B);
    final subtitle = verified
        ? 'Verified \u00b7 end-to-end encrypted'
        : changed
        ? 'Key changed \u00b7 verify before sending'
        : 'End-to-end encrypted \u00b7 verify key';
    return Material(
      color: dark ? const Color(0xFF1A2925) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dark ? const Color(0xFF2E4840) : const Color(0xFFE2EAE6),
            ),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _ProfileAvatar(
                    username: widget.name,
                    userId: widget.peer?['id']?.toString(),
                    photoUrl: widget.peer?['photoUrl']?.toString(),
                    size: 48,
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF1A2925) : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        verified
                            ? Icons.verified_user_rounded
                            : changed
                            ? Icons.warning_amber_rounded
                            : Icons.shield_outlined,
                        size: 15,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: changed ? colors.error : colors.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityCard extends StatefulWidget {
  const _SecurityCard({required this.session});
  final ChatSession session;

  @override
  State<_SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends State<_SecurityCard> {
  bool? screenSecure;

  @override
  void initState() {
    super.initState();
    SecurityPrefs.screenSecureEnabled().then((value) {
      if (mounted) setState(() => screenSecure = value);
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Block screenshots'),
          subtitle: const Text(
            'Hide chats from screenshots, screen recording and the recent-apps preview',
          ),
          value: screenSecure ?? true,
          activeThumbColor: _brand,
          onChanged: screenSecure == null
              ? null
              : (value) async {
                  setState(() => screenSecure = value);
                  await SecurityPrefs.setScreenSecure(value);
                },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: const Text(
            'Lock CrazeChat now',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Remove the unlocked key from memory until you enter your password',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => unawaited(widget.session.lock()),
        ),
        const Divider(height: 1),
        const ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text(
            'Contact keys',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Open a chat and compare the fingerprint with your contact. Sending stays blocked until you verify it.',
          ),
        ),
      ],
    ),
  );
}

class _FindPeopleDialog extends StatefulWidget {
  const _FindPeopleDialog({required this.session});
  final ChatSession session;

  @override
  State<_FindPeopleDialog> createState() => _FindPeopleDialogState();
}

class _FindPeopleDialogState extends State<_FindPeopleDialog> {
  final controller = TextEditingController();
  Timer? debounce;
  List<Map<String, dynamic>> users = [];
  bool searching = false;
  String? error;
  String query = '';

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    query = value.trim();
    debounce?.cancel();
    if (query.length < 2) {
      setState(() {
        users = [];
        searching = false;
        error = null;
      });
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    debounce = Timer(const Duration(milliseconds: 320), _runSearch);
  }

  Future<void> _runSearch() async {
    final requested = query;
    try {
      final result = await widget.session.api.searchUsers(requested);
      if (!mounted || requested != query) return;
      final values = (result['users'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where((value) => value['id'] != widget.session.userId)
          .toList();
      setState(() {
        users = values;
        searching = false;
        error = null;
      });
    } catch (exception) {
      if (!mounted || requested != query) return;
      setState(() {
        users = [];
        searching = false;
        error = exception.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Find people',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Search by username',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            controller.clear();
                            _search('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: searching
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Center(
                            child: Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                          )
                        : users.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 34),
                                  child: Text(
                                    query.length < 2
                                        ? 'Enter at least 2 characters to find people.'
                                        : 'No users found for \u201c$query\u201d.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: users.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  final username =
                                      user['username']?.toString() ?? 'User';
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: _ProfileAvatar(
                                      username: username,
                                      userId: user['id']?.toString(),
                                      photoUrl: user['photoUrl']?.toString(),
                                      size: 42,
                                    ),
                                    title: Text(
                                      '@$username',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: const Text('Start a private chat'),
                                    trailing: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                    onTap: () =>
                                        Navigator.pop(context, username),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalFolderSyncCard extends StatefulWidget {
  const _LocalFolderSyncCard({required this.session});
  final ChatSession session;

  @override
  State<_LocalFolderSyncCard> createState() => _LocalFolderSyncCardState();
}

class _LocalFolderSyncCardState extends State<_LocalFolderSyncCard> {
  final service = LocalFolderSyncService.instance;
  String? _loadedUserId;

  @override
  void initState() {
    super.initState();
    _loadedUserId = widget.session.userId;
    unawaited(service.refreshStatus(widget.session));
  }

  @override
  void didUpdateWidget(covariant _LocalFolderSyncCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentUserId = widget.session.userId;
    if (currentUserId != _loadedUserId) {
      _loadedUserId = currentUserId;
      unawaited(service.refreshStatus(widget.session));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final lastSync = service.lastSyncedAt;
      final lastSyncLabel = lastSync == null
          ? null
          : '${MaterialLocalizations.of(context).formatMediumDate(lastSync)} \u00b7 '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastSync))}';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Local Folder Sync',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          service.folderSelected
                              ? 'A backup folder is selected'
                              : 'Choose where your encrypted backup is stored',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (service.syncing)
                    const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'CrazeChat writes an encrypted backup file into a folder you choose. '
                'The folder can be on your device or an Android document provider.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The backup contains encrypted message envelopes only. Restoring requires the same CrazeChat identity.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              if (lastSyncLabel != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Last saved: $lastSyncLabel',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
              if (service.status != null) ...[
                const SizedBox(height: 8),
                Text(
                  service.status!,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    onPressed: service.syncing
                        ? null
                        : () => _run(
                            () => service.chooseFolderAndSync(widget.session),
                          ),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(
                      service.folderSelected ? 'Change folder' : 'Choose folder',
                    ),
                  ),
                  if (service.folderSelected)
                    OutlinedButton.icon(
                      onPressed: service.syncing
                          ? null
                          : () => _run(() => service.syncNow(widget.session)),
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Sync now'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 5),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: colors.onSecondaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colors.onSurfaceVariant,
        ),
        onTap: onTap,
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
  double _replyDragDistance = 0;
  final input = TextEditingController();
  final composerFocus = FocusNode();
  final scroll = ScrollController();
  final search = TextEditingController();
  // True while the user has scrolled away from the newest message; drives the
  // floating "jump to latest" button without rebuilding the message list.
  final ValueNotifier<bool> _showJump = ValueNotifier<bool>(false);
  List<Map<String, dynamic>> messages = [];
  final Set<String> messageIds = <String>{};
  // Messages that arrived live (not from history) and still need their
  // one-time entrance animation. History and scrolled-back items never animate.
  final Set<String> _freshIds = <String>{};
  bool _firstSyncDone = false;
  int _pollTicks = 0;
  SecretKey? chatKey;
  String? peerName, error, peerId, peerPublicKey, peerFingerprint;
  String peerKeyStatus = 'unverified';
  Map<String, dynamic>? replyTarget;
  bool loading = true, sending = false, syncing = false, searchOpen = false;
  int? lastServerMessageAt;
  WebSocket? realtime;
  StreamSubscription? realtimeSubscription;
  Timer? reconnectTimer;
  Timer? syncTimer;
  Timer? pollTimer;
  Timer? readAckTimer;
  final Set<String> pendingReadAcks = <String>{};
  bool connectingRealtime = false;
  bool retryingPending = false;
  int reconnectAttempt = 0;

  String get chatId => widget.chat['id'] as String;

  // Advance the incremental-sync cursor only from server-authoritative
  // timestamps. Device clocks and optimistic outbox timestamps are untrusted.
  void _advanceServerMessageCursor(Object? value) {
    final timestamp = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    if (timestamp <= 0) return;
    if (lastServerMessageAt == null || timestamp > lastServerMessageAt!) {
      lastServerMessageAt = timestamp;
    }
  }

  static const int _maxMessageWords = 1500;

  int _wordCount(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
  }
  Map<String, dynamic>? get peer {
    final members = (widget.chat['members'] as List? ?? const [])
        .whereType<Map>()
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
    scroll.addListener(_onScroll);
    // Keep a REST polling fallback active even when the realtime socket is
    // unavailable or silently disconnected by a mobile network/proxy.
    // While the WebSocket is connected it delivers new messages and read
    // receipts, so the poll only runs every 30 seconds as a safety net
    // (delivered receipts, missed events). Without a socket it stays at 5 s.
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || loading || syncing || chatKey == null) return;
      if (realtime != null) {
        _pollTicks = (_pollTicks + 1) % 6;
        if (_pollTicks != 0) return;
      } else {
        _pollTicks = 0;
      }
      await loadMessages(silent: true);
    });
    syncTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted) return;
      await _retryPendingMessages();
    });
    prepare();
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    syncTimer?.cancel();
    pollTimer?.cancel();
    readAckTimer?.cancel();
    realtimeSubscription?.cancel();
    realtime?.close();
    input.dispose();
    composerFocus.dispose();
    search.removeListener(_searchChanged);
    search.dispose();
    scroll.removeListener(_onScroll);
    scroll.dispose();
    _showJump.dispose();
    super.dispose();
  }

  void _searchChanged() => setState(() {});

  void _onScroll() {
    if (!scroll.hasClients) return;
    final away = scroll.position.maxScrollExtent - scroll.position.pixels > 320;
    if (_showJump.value != away) _showJump.value = away;
  }

  bool _isNearBottom() =>
      !scroll.hasClients ||
      scroll.position.maxScrollExtent - scroll.position.pixels < 240;

  // Open a conversation on its newest message instead of the oldest one.
  // Item heights are measured lazily, so settle once more on the next frame.
  void _jumpToBottomSoon() {
    void jump() {
      if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    });
  }

  bool _sameDay(int a, int b) {
    final x = DateTime.fromMillisecondsSinceEpoch(a);
    final y = DateTime.fromMillisecondsSinceEpoch(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  String _dayLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final suffix = date.year == now.year ? '' : ', ${date.year}';
    return '${months[date.month - 1]} ${date.day}$suffix';
  }

  // Consecutive messages from the same sender within five minutes form one
  // visual group: tighter spacing and joined corners.
  bool _groupsWith(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = _time(a), tb = _time(b);
    return a['senderId'] == b['senderId'] &&
        ta > 0 &&
        tb > 0 &&
        _sameDay(ta, tb) &&
        (tb - ta).abs() < 5 * 60 * 1000;
  }

  Future<void> prepare() async {
    final other = peer;
    if (other == null || widget.session.identity == null) {
      if (mounted) {
        setState(() {
          error = 'This conversation is missing an encryption identity.';
          loading = false;
        });
      }
      return;
    }
    peerName = other['username']?.toString() ?? 'Conversation';
    peerId = other['id']?.toString();
    peerPublicKey = other['publicKey'] as String?;
    try {
      if (peerId == null || peerPublicKey == null || peerPublicKey!.isEmpty) {
        throw const FormatException('Contact public key is missing.');
      }
      peerFingerprint = await CryptoService.fingerprintPublicKey(peerPublicKey!);
      peerKeyStatus = await widget.session.contactKeyStatus(
        contactId: peerId!,
        publicKey: peerPublicKey!,
      );
      chatKey = await CryptoService.deriveChatKey(
        myKeyPair: widget.session.identity!,
        peerPublicKey: peerPublicKey!,
        chatId: chatId,
      );
      final cached = await widget.session.loadCachedMessages(chatId);
      // Local encrypted history is authoritative after the server purges a
      // read message. Never hide a cached message based on its delivery state.
      for (final message in cached) {
        await _addLocalMessage(message);
      }
      messages.sort((a, b) => _time(a).compareTo(_time(b)));
      if (mounted) {
        setState(() => loading = false);
        _jumpToBottomSoon();
      }
      // Do not fetch or decrypt remote messages until this contact's public
      // key has been independently verified. Local encrypted history remains
      // available while the user checks the fingerprint.
      if (peerKeyStatus == 'verified') {
        unawaited(loadMessages(silent: true));
        _connectRealtime();
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = 'Could not establish the encrypted conversation: $exception';
          loading = false;
        });
      }
    }
  }

  Future<void> _showPeerVerification() async {
    final id = peerId;
    final publicKey = peerPublicKey;
    final fingerprint = peerFingerprint;
    if (id == null || publicKey == null || fingerprint == null) return;
    final changed = peerKeyStatus == 'changed';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          Icon(changed ? Icons.warning_amber_rounded : Icons.fingerprint_rounded,
              color: changed ? Colors.orange : _brand),
          const SizedBox(width: 10),
          Expanded(child: Text(changed ? 'Contact key changed' : 'Verify contact key')),
        ]),
        content: SelectableText(
          'Contact: @${peerName ?? 'contact'}\n\nSHA-256 fingerprint:\n$fingerprint\n\nCompare this entire fingerprint with your contact using a separate trusted channel (in person or a call). Do not trust a fingerprint sent only through this chat. '
          '${changed ? 'The public key differs from the one previously verified. Sending remains blocked until you independently confirm this replacement key.' : 'This key is not verified on this device yet. Sending remains blocked until you compare and confirm it.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I compared and verified'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.session.trustContactKey(contactId: id, publicKey: publicKey);
      if (mounted) {
        setState(() => peerKeyStatus = 'verified');
        unawaited(loadMessages(silent: true));
        _connectRealtime();
      }
    }
  }

  Future<void> _connectRealtime() async {
    if (!mounted || connectingRealtime || realtime != null) return;
    connectingRealtime = true;
    try {
      final socket = await widget.session.api.connectRealtime(chatId);
      if (!mounted) {
        await socket.close();
        return;
      }
      realtime = socket;
      reconnectAttempt = 0;
      reconnectTimer?.cancel();
      realtimeSubscription = socket.listen(
        (event) => _handleRealtimeEvent(event),
        onError: (_) => _scheduleRealtimeReconnect(),
        onDone: _scheduleRealtimeReconnect,
        cancelOnError: true,
      );
      await loadMessages(silent: true);
    } catch (_) {
      _scheduleRealtimeReconnect();
    } finally {
      connectingRealtime = false;
    }
  }

  void _scheduleRealtimeReconnect() {
    final oldSubscription = realtimeSubscription;
    final oldSocket = realtime;
    realtimeSubscription = null;
    realtime = null;
    oldSubscription?.cancel();
    oldSocket?.close();
    if (!mounted || reconnectTimer?.isActive == true) return;
    final seconds = 2 * (1 << reconnectAttempt.clamp(0, 5).toInt());
    reconnectAttempt = (reconnectAttempt + 1).clamp(0, 6).toInt();
    reconnectTimer = Timer(
      Duration(seconds: seconds.clamp(2, 60).toInt()),
      () async {
        if (!mounted) return;
        await _retryPendingMessages();
        _connectRealtime();
      },
    );
  }

  Future<void> _acknowledgeIncoming(
    List<String> ids, {
    required String status,
  }) async {
    if (ids.isEmpty) {
      return;
    }
    for (var start = 0; start < ids.length; start += 100) {
      final batch = ids.skip(start).take(100).toList();
      try {
        await widget.session.api.acknowledgeMessages(
          chatId,
          messageIds: batch,
          status: status,
        );
        // A successful read acknowledgement lets the backend purge its
        // server-side payload. The encrypted local copy and ChatView entry
        // must remain untouched so the conversation survives future launches.
      } catch (_) {
        // Keep the local copy if the server did not confirm the purge.
      }
    }
  }

  Future<void> _scheduleReadPurge(List<String> ids) async {
    if (ids.isEmpty) return;
    // Coalesce realtime arrivals into one acknowledgement request. The IDs
    // are queued only after their encrypted envelopes have been persisted.
    pendingReadAcks.addAll(ids);
    readAckTimer ??= Timer(const Duration(milliseconds: 350), () {
      readAckTimer = null;
      final batch = pendingReadAcks.toList();
      pendingReadAcks.clear();
      unawaited(_acknowledgeIncoming(batch, status: 'read'));
    });
  }

  String _outgoingState(Map<String, dynamic> message) {
    final local = message['deliveryState']?.toString() ?? '';
    if (local == 'queued') return 'queued';
    final recipientId = peer?['id']?.toString();
    final readBy = message['readBy'];
    if (recipientId != null &&
        readBy is Map &&
        readBy.containsKey(recipientId)) {
      return 'read';
    }
    final deliveredTo = message['deliveredTo'];
    if (recipientId != null &&
        deliveredTo is Map &&
        deliveredTo.containsKey(recipientId)) {
      return 'delivered';
    }
    return 'sent';
  }

  // The server sends `message_deleted` to the sender when the recipient has
  // read (and the server has purged) those messages. That is a read receipt
  // for our own messages; it never deletes anything from local history.
  Future<void> _applyPeerReadReceipts(Object? rawIds) async {
    final recipientId = peer?['id']?.toString();
    final me = widget.session.userId;
    if (recipientId == null || me == null || rawIds is! List) return;
    final readAt = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, Map<String, dynamic>>{};
    for (final raw in rawIds) {
      final id = raw?.toString();
      if (id == null) continue;
      final index = messages.indexWhere(
        (item) => item['id'] == id && item['senderId'] == me,
      );
      if (index < 0) continue;
      final readBy = Map<String, dynamic>.from(
        messages[index]['readBy'] is Map
            ? messages[index]['readBy'] as Map
            : const {},
      );
      if (readBy.containsKey(recipientId)) continue;
      readBy[recipientId] = readAt;
      messages[index]['readBy'] = readBy;
      updates[id] = readBy;
    }
    if (updates.isEmpty) return;
    if (mounted) setState(() {});
    for (final entry in updates.entries) {
      try {
        final index = messages.indexWhere((item) => item['id'] == entry.key);
        final state = index >= 0
            ? (messages[index]['deliveryState']?.toString() ?? 'sent')
            : 'sent';
        await widget.session.updateCachedMessage(
          chatId,
          entry.key,
          deliveryState: state,
          serverMessage: {'readBy': entry.value},
        );
      } catch (_) {
        // The on-screen state is already updated; the next sync repairs the cache.
      }
    }
  }

  Future<void> _handleRealtimeEvent(dynamic event) async {
    try {
      final decodedEvent = jsonDecode(event.toString());
      if (decodedEvent is! Map) return;
      if (decodedEvent['type'] == 'message_deleted') {
        // This event describes deletion of the remote Firebase copy only.
        // Never propagate it into the local message history; use it solely
        // as a read receipt for messages this account sent.
        await _applyPeerReadReceipts(decodedEvent['messageIds']);
        return;
      }
      if (decodedEvent['type'] != 'message' ||
          decodedEvent['message'] is! Map) {
        return;
      }
      final message = Map<String, dynamic>.from(decodedEvent['message'] as Map);
      final id = message['id']?.toString();
      if (id == null ||
          message['senderId'] == widget.session.userId ||
          messageIds.contains(id)) {
        return;
      }
      final decoded = await _decodeMessage(message);
      await widget.session.saveCachedMessage(chatId, {
        ...message,
        'deliveryState': 'saved',
      });
      LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
      // A REST sync can finish while this event is being decrypted and saved.
      // Recheck after the awaits so the same envelope is never shown twice.
      if (messageIds.contains(id)) return;
      message['deliveryState'] = 'saved';
      messageIds.add(id);
      _freshIds.add(id);
      _advanceServerMessageCursor(message['createdAt']);
      if (mounted) {
        // Only follow new messages when the reader is already at the bottom;
        // otherwise leave their scroll position alone and offer a jump button.
        final followNewest = _isNearBottom();
        setState(() {
          _applyDecodedMessage(decoded);
          messages.sort((a, b) => _time(a).compareTo(_time(b)));
        });
        if (decoded['messageKind'] != 'reaction') {
          if (followNewest) {
            _scrollToBottom();
          } else {
            _showJump.value = true;
          }
        }
        unawaited(
          CrazeChatSoundEffects.playIncoming(
            enabled: widget.session.soundEffectsEnabled,
          ),
        );
        if (widget.session.vibrationEnabled) {
          HapticFeedback.mediumImpact();
        }
      }
      unawaited(_scheduleReadPurge([id]));
    } catch (_) {
      // The next reconnect sync recovers any event that could not be processed.
    }
  }

  Future<Map<String, dynamic>> _decodeMessage(
    Map<String, dynamic> message,
  ) async {
    final clear = await CryptoService.decryptMessage(
      message: message,
      chatKey: chatKey!,
      chatId: chatId,
    );
    try {
      final payload = jsonDecode(clear);
      if (payload is Map && payload['__cc_type'] == 'reaction') {
        return {
          ...message,
          'messageKind': 'reaction',
          'reactionTargetId': payload['targetId']?.toString(),
          'reactionEmoji': payload['emoji']?.toString() ?? '',
        };
      }
      if (payload is Map && payload['__cc_type'] == 'message') {
        return {
          ...message,
          'messageKind': 'text',
          'clearText': payload['text']?.toString() ?? '',
          if (payload['replyTo'] is Map)
            'replyTo': Map<String, dynamic>.from(payload['replyTo'] as Map),
        };
      }
    } catch (_) {
      // Plain-text payloads from earlier versions remain readable.
    }
    return {...message, 'messageKind': 'text', 'clearText': clear};
  }

  void _applyDecodedMessage(Map<String, dynamic> message) {
    if (message['messageKind'] == 'reaction') {
      final targetId = message['reactionTargetId']?.toString();
      final senderId = message['senderId']?.toString();
      if (targetId != null && senderId != null) {
        final index = messages.indexWhere((item) => item['id'] == targetId);
        if (index >= 0) {
          final reactions = Map<String, dynamic>.from(
            messages[index]['reactionsByUser'] is Map
                ? messages[index]['reactionsByUser'] as Map
                : const {},
          );
          final emoji = message['reactionEmoji']?.toString() ?? '';
          if (emoji.isEmpty) {
            reactions.remove(senderId);
          } else {
            reactions[senderId] = emoji;
          }
          messages[index]['reactionsByUser'] = reactions;
        }
      }
      // Keep encrypted reaction events in the local timeline for replay after
      // restart, but they are not rendered as standalone message bubbles.
      messages.add(message);
      return;
    }
    final id = message['id']?.toString();
    if (id != null && messages.any((item) => item['id'] == id)) return;
    messages.add(message);
  }

  Future<void> _addLocalMessage(Map<String, dynamic> message) async {
    if (!mounted) return;
    final id = message['id']?.toString();
    if (id == null || messageIds.contains(id)) return;
    try {
      final decoded = await _decodeMessage(message);
      if (!mounted) return;
      messageIds.add(id);
      // Cached entries can carry device-generated timestamps (including
      // queued messages). They are timeline data, never a server sync cursor.
      _applyDecodedMessage(decoded);
    } catch (_) {
      // A damaged cache entry can be recovered from remote sync if it remains.
    }
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (chatKey == null || syncing || peerKeyStatus != 'verified') return;
    syncing = true;
    final followNewest = _isNearBottom();
    var addedVisible = false;
    try {
      if (!silent) await _retryPendingMessages();
      final messageResponse = await widget.session.api.getMessages(
        chatId,
        since: lastServerMessageAt == null ? null : lastServerMessageAt! - 1,
        limit: 100,
      );
      final raw = (messageResponse['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();

      final receivedIds = <String>[];
      for (final message in raw) {
        final id = message['id']?.toString();
        if (id == null) continue;
        final mine = message['senderId'] == widget.session.userId;
        try {
          // Decrypt first, then persist the encrypted envelope locally.
          final decoded = await _decodeMessage(message);
          await widget.session.saveCachedMessage(chatId, {
            ...message,
            'deliveryState': mine ? 'sent' : 'saved',
          });
          if (!mine) receivedIds.add(id);
          _advanceServerMessageCursor(message['createdAt']);
          if (!messageIds.contains(id)) {
            messageIds.add(id);
            if (_firstSyncDone) _freshIds.add(id);
            if (decoded['messageKind'] != 'reaction') addedVisible = true;
            _applyDecodedMessage(decoded);
          } else {
            final index = messages.indexWhere((item) => item['id'] == id);
            if (index >= 0) {
              final priorReactions = messages[index]['reactionsByUser'];
              final priorReadBy = messages[index]['readBy'];
              final serverReadBy = decoded['readBy'];
              messages[index] = {
                ...decoded,
                if (priorReactions is Map) 'reactionsByUser': priorReactions,
                // Keep a read receipt that arrived over the socket even if the
                // server copy has already been purged of it.
                if (priorReadBy is Map)
                  'readBy': {
                    ...priorReadBy,
                    if (serverReadBy is Map) ...serverReadBy,
                  },
              };
            }
          }
        } catch (exception) {
          if (!silent && mounted) {
            showMessage(
              context,
              'Could not save message $id locally: $exception',
            );
          }
        }
      }

      // Every received envelope above has been durably saved before the
      // read acknowledgement can trigger server-side deletion.
      await _scheduleReadPurge(receivedIds);
      messages.sort((a, b) => _time(a).compareTo(_time(b)));
      if (raw.isNotEmpty) {
        LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
      }
      _firstSyncDone = true;
      if (mounted) {
        setState(() {
          loading = false;
          error = null;
        });
      }
      if (!silent || (addedVisible && followNewest)) {
        _scrollToBottom();
      } else if (addedVisible) {
        _showJump.value = true;
      }
    } catch (exception) {
      // Automatic polling is quiet (no snackbar), but a failed REST pull must
      // remain visible instead of being presented as an empty conversation.
      if (mounted) {
        setState(() {
          error = exception.toString();
          loading = false;
        });
      }
    } finally {
      syncing = false;
    }
  }

  Future<void> _retryPendingMessages() async {
    if (retryingPending || !mounted || peerKeyStatus != 'verified') return;
    retryingPending = true;
    try {
      final cached = await widget.session.loadCachedMessages(chatId);
      for (final item in cached) {
        if (item['senderId'] != widget.session.userId ||
            item['deliveryState'] != 'queued') {
          continue;
        }
        final id = item['id']?.toString();
        if (id == null) continue;
        try {
          final decoded = await _decodeMessage(item);
          if (decoded['messageKind'] == 'text' &&
              _wordCount(decoded['clearText']?.toString() ?? '') >
                  _maxMessageWords) {
            if (mounted) {
              showMessage(context, 'A queued message exceeds the 1,500-word limit and was not sent.');
            }
            continue;
          }
          final response = await widget.session.api.sendMessage(chatId, {
            'id': id,
            'format': item['format'],
            'ciphertext': item['ciphertext'],
            'nonce': item['nonce'],
            'mac': item['mac'],
          });
          final serverMessage = Map<String, dynamic>.from(
            response['message'] as Map,
          );
          await widget.session.updateCachedMessage(
            chatId,
            id,
            deliveryState: 'sent',
            serverMessage: serverMessage,
          );
          _advanceServerMessageCursor(serverMessage['createdAt']);
          if (mounted) {
            final index = messages.indexWhere((message) => message['id'] == id);
            if (index >= 0) {
              setState(() {
                messages[index]['deliveryState'] = 'sent';
                if (serverMessage.containsKey('deliveredTo')) {
                  messages[index]['deliveredTo'] = serverMessage['deliveredTo'];
                }
                if (serverMessage.containsKey('readBy')) {
                  messages[index]['readBy'] = serverMessage['readBy'];
                }
              });
            }
          }
        } on ApiException catch (exception) {
          if (exception.statusCode != null &&
              exception.statusCode! >= 400 &&
              exception.statusCode! < 500 &&
              exception.statusCode != 429 &&
              mounted) {
            showMessage(
              context,
              'A queued message needs attention: ${exception.message}',
            );
          }
        } catch (_) {
          // Keep the encrypted item queued; the next sync cycle retries it.
        }
      }
    } finally {
      retryingPending = false;
    }
  }

  Future<void> send() async {
    if (peerKeyStatus != 'verified') {
      showMessage(context, 'Verify this contact\'s public-key fingerprint before sending messages.');
      await _showPeerVerification();
      return;
    }
    final text = input.text.trim();
    if (text.isEmpty || sending || chatKey == null) return;
    final words = _wordCount(text);
    if (words > _maxMessageWords) {
      showMessage(context, 'Messages can contain up to 1,500 words.');
      return;
    }
    final reply = replyTarget == null
        ? null
        : <String, dynamic>{
            'id': replyTarget!['id'],
            'senderId': replyTarget!['senderId'],
            'text': replyTarget!['clearText']?.toString() ?? '',
          };
    final encryptedText = jsonEncode({
      '__cc_type': 'message',
      'text': text,
      'replyTo': reply,
    });
    setState(() => sending = true);
    input.clear();
    final id = widget.session.api.createMessageId();
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final encrypted = await CryptoService.encryptMessage(
        text: encryptedText,
        chatKey: chatKey!,
        chatId: chatId,
        senderId: widget.session.userId!,
      );
      final queued = <String, dynamic>{
        'id': id,
        'senderId': widget.session.userId,
        ...encrypted,
        'createdAt': createdAt,
        'deliveryState': 'queued',
      };
      // Persist the encrypted envelope before the server can expose it.
      await widget.session.saveCachedMessage(chatId, queued);
      LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
      if (mounted) {
        setState(() {
          messages.add({
            ...queued,
            'messageKind': 'text',
            'clearText': text,
            if (reply != null) 'replyTo': reply,
          });
          messageIds.add(id);
          _freshIds.add(id);
          replyTarget = null;
        });
      }
      _scrollToBottom();
      unawaited(
        CrazeChatSoundEffects.playOutgoing(
          enabled: widget.session.soundEffectsEnabled,
        ),
      );
      if (widget.session.vibrationEnabled) {
        HapticFeedback.lightImpact();
      }
      try {
        final response = await widget.session.api.sendMessage(chatId, {
          'id': id,
          'format': encrypted['format'],
          'ciphertext': encrypted['ciphertext'],
          'nonce': encrypted['nonce'],
          'mac': encrypted['mac'],
        });
        final serverMessage = Map<String, dynamic>.from(
          response['message'] as Map,
        );
        await widget.session.updateCachedMessage(
          chatId,
          id,
          deliveryState: 'sent',
          serverMessage: serverMessage,
        );
        // Keep the live timeline cursor aligned with the same server timestamp
        // already persisted in the encrypted local cache.
        _advanceServerMessageCursor(serverMessage['createdAt']);
        LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
        if (mounted) {
          final index = messages.indexWhere((item) => item['id'] == id);
          if (index >= 0) {
            setState(() {
              messages[index]['deliveryState'] = 'sent';
              // Keep the rendered bubble aligned with the server timestamp.
              // Its timestamp is independent from the retrieval cursor.
              final serverCreatedAt = (serverMessage['createdAt'] as num?)?.toInt();
              if (serverCreatedAt != null) {
                messages[index]['createdAt'] = serverCreatedAt;
              }
              if (serverMessage.containsKey('deliveredTo')) {
                messages[index]['deliveredTo'] = serverMessage['deliveredTo'];
              }
              if (serverMessage.containsKey('readBy')) {
                messages[index]['readBy'] = serverMessage['readBy'];
              }
            });
          }
        }
      } catch (_) {
        if (mounted) {
          showMessage(
            context,
            'Saved to your outbox. CrazeChat will retry when the connection returns.',
          );
        }
      }
    } catch (exception) {
      input.text = text;
      if (mounted) showMessage(context, exception.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> reactToMessage(Map<String, dynamic> target, String emoji) async {
    if (peerKeyStatus != 'verified') {
      showMessage(context, 'Verify this contact\'s public-key fingerprint before sending reactions.');
      await _showPeerVerification();
      return;
    }
    if (chatKey == null || sending) return;
    final targetId = target['id']?.toString();
    final senderId = widget.session.userId;
    if (targetId == null || senderId == null) return;
    final current = Map<String, dynamic>.from(
      target['reactionsByUser'] is Map
          ? target['reactionsByUser'] as Map
          : const {},
    );
    final nextEmoji = current[senderId] == emoji ? '' : emoji;
    final payload = jsonEncode({
      '__cc_type': 'reaction',
      'targetId': targetId,
      'emoji': nextEmoji,
    });
    final id = widget.session.api.createMessageId();
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final encrypted = await CryptoService.encryptMessage(
        text: payload,
        chatKey: chatKey!,
        chatId: chatId,
        senderId: senderId,
      );
      final queued = <String, dynamic>{
        'id': id,
        'senderId': senderId,
        ...encrypted,
        'createdAt': createdAt,
        'deliveryState': 'queued',
      };
      await widget.session.saveCachedMessage(chatId, queued);
      LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
      if (!mounted) return;
      setState(() {
        messageIds.add(id);
        _applyDecodedMessage({
          ...queued,
          'messageKind': 'reaction',
          'reactionTargetId': targetId,
          'reactionEmoji': nextEmoji,
        });
      });
      unawaited(
        CrazeChatSoundEffects.playOutgoing(
          enabled: widget.session.soundEffectsEnabled,
        ),
      );
      if (widget.session.vibrationEnabled) {
        HapticFeedback.selectionClick();
      }
      try {
        final response = await widget.session.api.sendMessage(chatId, {
          'id': id,
          'format': encrypted['format'],
          'ciphertext': encrypted['ciphertext'],
          'nonce': encrypted['nonce'],
          'mac': encrypted['mac'],
        });
        final serverMessage = Map<String, dynamic>.from(
          response['message'] as Map,
        );
        await widget.session.updateCachedMessage(
          chatId,
          id,
          deliveryState: 'sent',
          serverMessage: serverMessage,
        );
        _advanceServerMessageCursor(serverMessage['createdAt']);
        LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
      } catch (_) {
        if (mounted) {
          showMessage(context, 'Reaction queued until the connection returns.');
        }
      }
    } catch (exception) {
      if (mounted) showMessage(context, 'Could not save reaction: $exception');
    }
  }

  void _startReply(Map<String, dynamic> message) {
    if (message['messageKind'] == 'reaction') return;
    setState(() {
      replyTarget = {
        'id': message['id'],
        'senderId': message['senderId'],
        'clearText': message['clearText']?.toString() ?? '',
      };
    });
    FocusScope.of(context).requestFocus(composerFocus);
  }

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    final id = message['id']?.toString();
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text(
          'The server copy will be removed and a deletion receipt will synchronize to the other participant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep message'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9B3D35),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session.api.deleteMessage(chatId, id);
      await widget.session.deleteCachedMessage(chatId, id);
      LocalFolderSyncService.instance.scheduleAutomaticSync(widget.session);
      if (!mounted) return;
      setState(() {
        messages.removeWhere((item) => item['id'] == id);
        messageIds.remove(id);
      });
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
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startReply(message);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['\u2764\ufe0f', '\ud83d\ude02', '\ud83d\ude2e', '\ud83d\ude22', '\ud83d\ude4f', '\ud83d\udc4d']
                    .map(
                      (emoji) => InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          reactToMessage(message, emoji);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy message'),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: message['clearText']?.toString() ?? ''),
                );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (mounted) showMessage(context, 'Message copied.');
              },
            ),
            if (mine)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFF9B3D35),
                ),
                title: const Text('Delete message'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  deleteMessage(message);
                },
              ),
          ],
        ),
      ),
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

  int _time(Map<String, dynamic> message) =>
      (message['createdAt'] as num?)?.toInt() ?? 0;
  String _clock(Object? value) {
    final timestamp = value is num ? value.toInt() : 0;
    if (timestamp <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final searchQuery = search.text.trim().toLowerCase();
    final visible = messages
        .where(
          (message) =>
              message['messageKind'] != 'reaction' &&
              (searchQuery.isEmpty ||
                  (message['clearText']?.toString().toLowerCase() ?? '')
                      .contains(searchQuery)),
        )
        .toList();
    // Day labels (String) and message positions (int) in display order.
    final items = <Object>[];
    for (var i = 0; i < visible.length; i++) {
      final stamp = _time(visible[i]);
      if (stamp > 0 &&
          (i == 0 ||
              _time(visible[i - 1]) <= 0 ||
              !_sameDay(_time(visible[i - 1]), stamp))) {
        items.add(_dayLabel(stamp));
      }
      items.add(i);
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _ProfileAvatar(username: peerName ?? 'contact', userId: peerId, photoUrl: peer?['photoUrl']?.toString(), size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName ?? 'Conversation',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        peerKeyStatus == 'verified' ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                        size: 12,
                        color: peerKeyStatus == 'verified' ? _brand : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        peerKeyStatus == 'verified'
                            ? 'Contact key verified'
                            : peerKeyStatus == 'changed'
                                ? 'Contact key changed'
                                : 'Verify contact key',
                        style: TextStyle(
                          fontSize: 10,
                          color: peerKeyStatus == 'verified' ? colors.onSurfaceVariant : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Verify contact encryption key',
            onPressed: _showPeerVerification,
            icon: Icon(
              peerKeyStatus == 'verified' ? Icons.verified_user_rounded : Icons.fingerprint_rounded,
              color: peerKeyStatus == 'verified' ? _brand : Colors.orange,
            ),
          ),
          IconButton(
            tooltip: searchOpen ? 'Close search' : 'Search messages',
            onPressed: () => setState(() {
              searchOpen = !searchOpen;
              search.clear();
            }),
            icon: Icon(searchOpen ? Icons.close_rounded : Icons.search_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                controller: search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in this conversation',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          if (!loading && peerId != null && peerKeyStatus != 'verified')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Material(
                color: peerKeyStatus == 'changed'
                    ? colors.errorContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    peerKeyStatus == 'changed'
                        ? Icons.warning_amber_rounded
                        : Icons.fingerprint_rounded,
                    color: peerKeyStatus == 'changed'
                        ? colors.onErrorContainer
                        : Colors.orange,
                  ),
                  title: Text(
                    peerKeyStatus == 'changed'
                        ? 'This contact\u2019s key changed. Verify it before sending.'
                        : 'Verify ${peerName ?? 'this contact'}\u2019s key to send and receive new messages.',
                    style: TextStyle(
                      fontSize: 12,
                      color: peerKeyStatus == 'changed'
                          ? colors.onErrorContainer
                          : colors.onSurface,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _showPeerVerification,
                    child: const Text('Verify'),
                  ),
                ),
              ),
            ),
          if (error != null && !loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Material(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.cloud_off_outlined,
                    color: colors.onErrorContainer,
                  ),
                  title: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onErrorContainer,
                    ),
                  ),
                  trailing: IconButton(
                    onPressed: () => loadMessages(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null && messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_clock_outlined,
                            size: 48,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Conversation not synced',
                            style: TextStyle(color: colors.onSurface),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () => loadMessages(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _BrandMark(size: 52),
                          const SizedBox(height: 14),
                          Text(
                            search.text.isEmpty
                                ? 'This channel is yours.'
                                : 'No matching messages.',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Encrypted before sending. Saved on your device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey<String>('chat-message-list'),
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      if (item is String) {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      }
                      final messageIndex = item as int;
                      final message = visible[messageIndex];
                      final previous =
                          messageIndex > 0 ? visible[messageIndex - 1] : null;
                      final following = messageIndex + 1 < visible.length
                          ? visible[messageIndex + 1]
                          : null;
                      final joinedAbove =
                          previous != null && _groupsWith(previous, message);
                      final joinedBelow =
                          following != null && _groupsWith(message, following);
                      final mine = message['senderId'] == widget.session.userId;
                      final state = mine
                          ? _outgoingState(message)
                          : (message['deliveryState']?.toString() ?? '');
                      final reactions = Map<String, dynamic>.from(
                        message['reactionsByUser'] is Map
                            ? message['reactionsByUser'] as Map
                            : const {},
                      );
                      final reactionCounts = <String, int>{};
                      for (final value
                          in reactions.values.whereType<String>()) {
                        reactionCounts[value] =
                            (reactionCounts[value] ?? 0) + 1;
                      }
                      final reply = message['replyTo'] is Map
                          ? Map<String, dynamic>.from(message['replyTo'] as Map)
                          : null;
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final bubbleColor = mine
                          ? (isDark
                                ? const Color(0xFF17483D)
                                : const Color(0xFFE0F1E8))
                          : (isDark ? const Color(0xFF1A2925) : Colors.white);
                      final bubbleBorder = isDark
                          ? const Color(0xFF2E4840)
                          : (mine
                                ? const Color(0xFFC6E4D4)
                                : const Color(0xFFE5ECE8));
                      // One tail corner on the sender's side; inner corners of a
                      // group are tightened so consecutive bubbles read as one.
                      const round = Radius.circular(20);
                      const tight = Radius.circular(6);
                      final radius = mine
                          ? BorderRadius.only(
                              topLeft: round,
                              bottomLeft: round,
                              topRight: joinedAbove ? tight : round,
                              bottomRight: tight,
                            )
                          : BorderRadius.only(
                              topRight: round,
                              bottomRight: round,
                              topLeft: joinedAbove ? tight : round,
                              bottomLeft: tight,
                            );
                      final stateLabel = state == 'queued'
                          ? 'Waiting to send'
                          : state == 'read'
                          ? 'Read'
                          : state == 'delivered'
                          ? 'Delivered'
                          : 'Sent';
                      final meta = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _clock(message['createdAt']),
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (mine && state.isNotEmpty) ...[
                            const SizedBox(width: 3),
                            Semantics(
                              label: stateLabel,
                              child: Icon(
                                state == 'queued'
                                    ? Icons.schedule_rounded
                                    : (state == 'read' || state == 'delivered')
                                    ? Icons.done_all_rounded
                                    : Icons.check_rounded,
                                size: 14,
                                color: state == 'read'
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      );
                      final bubbleBox = Container(
                        padding: const EdgeInsets.fromLTRB(13, 9, 11, 7),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: radius,
                          border: Border.all(color: bubbleBorder),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reply != null)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * .68,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.fromLTRB(
                                    9,
                                    6,
                                    9,
                                    6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surface.withValues(
                                      alpha: .72,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border(
                                      left: BorderSide(
                                        color: colors.primary,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reply['senderId'] ==
                                                widget.session.userId
                                            ? 'You'
                                            : (peerName ?? 'Contact'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: colors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        reply['text']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // The time and delivery tick sit in the bottom-right
                            // corner of the text; a transparent spacer at the end
                            // of the text keeps the last line clear of them.
                            Stack(
                              children: [
                                Text.rich(
                                  TextSpan(
                                    text: message['clearText']?.toString() ?? '',
                                    children: [
                                      WidgetSpan(
                                        child: SizedBox(
                                          width: mine ? 62 : 40,
                                          height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.34,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Positioned(right: 0, bottom: 0, child: meta),
                              ],
                            ),
                          ],
                        ),
                      );
                      final bubble = Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .78,
                          ),
                          child: GestureDetector(
                            onLongPress: () => messageActions(message),
                            onHorizontalDragStart: (_) {
                              _replyDragDistance = 0;
                            },
                            onHorizontalDragUpdate: (details) {
                              _replyDragDistance += details.delta.dx;
                            },
                            onHorizontalDragEnd: (details) {
                              final thresholdReached =
                                  _replyDragDistance.abs() >= 64 ||
                                  (details.primaryVelocity?.abs() ?? 0) >= 450;
                              final swipedTowardCenter = mine
                                  ? _replyDragDistance < -32
                                  : _replyDragDistance > 32;
                              _replyDragDistance = 0;
                              if (thresholdReached && swipedTowardCenter) {
                                HapticFeedback.selectionClick();
                                _startReply(message);
                              }
                            },
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    (joinedBelow ? 2.0 : 10.0) +
                                    (reactionCounts.isEmpty ? 0.0 : 12.0),
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  bubbleBox,
                                  if (reactionCounts.isNotEmpty)
                                    Positioned(
                                      bottom: -12,
                                      left: mine ? 10 : null,
                                      right: mine ? null : 10,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: reactionCounts.entries
                                            .map(
                                              (reactionEntry) => Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                      right: 4,
                                                    ),
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  onTap: () => reactToMessage(
                                                    message,
                                                    reactionEntry.key,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: colors
                                                          .surfaceContainerHighest,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            18,
                                                          ),
                                                      border: Border.all(
                                                        color: colors
                                                            .outlineVariant,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${reactionEntry.key} ${reactionEntry.value}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: colors.onSurface,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      final messageId = message['id']?.toString();
                      // Only a message that just arrived plays the entrance
                      // animation, once. History and items scrolled back into
                      // view are built plain, so scrolling stays smooth.
                      if (messageId == null || !_freshIds.contains(messageId)) {
                        return KeyedSubtree(
                          key: ValueKey(message['id']),
                          child: bubble,
                        );
                      }
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(message['id']),
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        onEnd: () => _freshIds.remove(messageId),
                        builder: (context, progress, child) => Opacity(
                          opacity: progress,
                          child: Transform.translate(
                            offset: Offset(0, (1 - progress) * 10),
                            child: child,
                          ),
                        ),
                        child: bubble,
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 12,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _showJump,
                    builder: (context, show, _) => IgnorePointer(
                      ignoring: !show,
                      child: AnimatedOpacity(
                        opacity: show ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: FloatingActionButton.small(
                          heroTag: null,
                          tooltip: 'Jump to latest',
                          onPressed: () {
                            _showJump.value = false;
                            _scrollToBottom();
                          },
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: replyTarget == null
                        ? const SizedBox.shrink()
                        : Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.fromLTRB(12, 9, 7, 9),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(13),
                              border: Border(
                                left: BorderSide(
                                  color: colors.primary,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        replyTarget!['senderId'] ==
                                                widget.session.userId
                                            ? 'Replying to yourself'
                                            : 'Replying to ${peerName ?? 'contact'}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: colors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        replyTarget!['clearText']?.toString() ??
                                            '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cancel reply',
                                  onPressed: () =>
                                      setState(() => replyTarget = null),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          focusNode: composerFocus,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => send(),
                          decoration: const InputDecoration(
                            hintText: 'Write something\u2026',
                            prefixIcon: Icon(Icons.edit_note_rounded),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        height: 48,
                        // Only the send button reacts to typing; the message
                        // list above is not rebuilt on every keystroke.
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: input,
                          builder: (context, value, _) {
                            final words = _wordCount(value.text);
                            final canSend =
                                !sending &&
                                words > 0 &&
                                words <= _maxMessageWords;
                            return AnimatedScale(
                              scale: sending ? .94 : 1,
                              duration: const Duration(milliseconds: 140),
                              child: Tooltip(
                                message: sending
                                    ? 'Sending message'
                                    : 'Send message',
                                child: FilledButton(
                                  onPressed: canSend ? send : null,
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: colors.primary,
                                    foregroundColor: colors.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: sending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.arrow_upward_rounded),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  // The word counter only appears once a message gets long.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: input,
                    builder: (context, value, _) {
                      final words = _wordCount(value.text);
                      if (words < 800) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(
                          top: 5,
                          left: 4,
                          right: 4,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$words / 1,500 words',
                            style: TextStyle(
                              fontSize: 10,
                              color: words > _maxMessageWords
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
