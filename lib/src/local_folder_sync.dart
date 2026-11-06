import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_service.dart';
import 'session.dart';

/// Encrypted backup stored in a user-selected Android SAF folder.
class LocalFolderSyncService extends ChangeNotifier {
  LocalFolderSyncService._();
  static final LocalFolderSyncService instance = LocalFolderSyncService._();

  static const _channel = MethodChannel('com.crazestudio.crazechat/local_sync');
  static const _storage = FlutterSecureStorage();
  static const _maxArchiveBytes = 64 * 1024 * 1024;
  static const _timeout = Duration(seconds: 45);

  Future<void>? _activeSync;
  Timer? _debounce;
  ChatSession? _pendingSession;
  String? _activeUserId;
  String? _folderUri;
  DateTime? _lastSyncedAt;
  bool _syncing = false;
  String? _status;

  bool get folderSelected => _folderUri != null;
  bool get syncing => _syncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get status => _status;

  static String _folderKey(String userId) => 'cc_local_sync_folder_$userId';
  static String _lastSyncKey(String userId) => 'cc_local_sync_last_$userId';

  Future<void> refreshStatus(ChatSession session) async {
    final userId = session.userId;
    _activeUserId = userId;
    if (userId == null) {
      _folderUri = null;
      _lastSyncedAt = null;
      notifyListeners();
      return;
    }
    final values = await Future.wait([
      _storage.read(key: _folderKey(userId)),
      _storage.read(key: _lastSyncKey(userId)),
    ]);
    if (session.userId != userId) return;
    _folderUri = values[0];
    final timestamp = int.tryParse(values[1] ?? '');
    _lastSyncedAt = timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    notifyListeners();
  }

  Future<void> chooseFolderAndSync(ChatSession session) async {
    final uri = await _channel.invokeMethod<String>('selectFolder');
    if (uri == null || uri.isEmpty) return;
    final userId = session.userId;
    if (userId == null) throw StateError('Sign in before selecting a sync folder.');
    await _storage.write(key: _folderKey(userId), value: uri);
    _folderUri = uri;
    notifyListeners();
    await _runSync(session);
  }

  Future<void> syncNow(ChatSession session) async {
    if (_folderUri == null) {
      throw StateError('Choose a local folder first.');
    }
    await _runSync(session);
  }

  Future<void> syncIfEnabled(ChatSession session) async {
    final userId = session.userId;
    if (userId == null || session.identity == null) return;
    final uri = await _storage.read(key: _folderKey(userId));
    if (uri == null || session.userId != userId) return;
    _folderUri = uri;
    try {
      await _runSync(session);
    } catch (error) {
      _status = 'Local folder sync needs attention: $error';
      notifyListeners();
    }
  }

  void scheduleAutomaticSync(ChatSession session) {
    if (session.userId == null || session.identity == null) return;
    _pendingSession = session;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      final pending = _pendingSession;
      _pendingSession = null;
      if (pending != null) unawaited(syncIfEnabled(pending));
    });
  }

  Future<void> _runSync(ChatSession session) async {
    if (_activeSync != null) return _activeSync!;
    final task = _performSync(session);
    _activeSync = task.whenComplete(() {
      _activeSync = null;
    });
    return _activeSync!;
  }

  Future<void> _performSync(ChatSession session) async {
    final userId = session.userId;
    final identity = session.identity;
    final folderUri = _folderUri;
    if (userId == null || identity == null || folderUri == null) {
      throw StateError('Unlock your CrazeChat identity and choose a folder first.');
    }
    _syncing = true;
    _activeUserId = userId;
    _status = 'Checking encrypted local backup…';
    notifyListeners();
    try {
      final existing = await _channel.invokeMethod<String>(
        'readBackup',
        {'treeUri': folderUri},
      ).timeout(_timeout);
      if (existing != null && existing.isNotEmpty) {
        _ensureIdentityActive(session, userId, identity);
        final envelope = Map<String, dynamic>.from(jsonDecode(existing) as Map);
        final archiveBytes = await CryptoService.decryptLocalBackup(
          envelope: envelope,
          identity: identity,
          userId: userId,
        );
        final decoded = jsonDecode(utf8.decode(archiveBytes));
        if (decoded is! Map) {
          throw const FormatException('Local encrypted backup is malformed.');
        }
        await session.mergeEncryptedLocalArchive(
          Map<String, dynamic>.from(decoded),
        );
      }

      _ensureIdentityActive(session, userId, identity);
      _status = 'Encrypting messages for local storage…';
      notifyListeners();
      final archive = await session.exportEncryptedLocalArchive();
      final archiveBytes = utf8.encode(jsonEncode(archive));
      if (archiveBytes.length > _maxArchiveBytes) {
        throw StateError('The encrypted archive is larger than the 64 MB sync limit.');
      }
      final encrypted = await CryptoService.encryptLocalBackup(
        archiveBytes: archiveBytes,
        identity: identity,
        userId: userId,
      );
      _ensureIdentityActive(session, userId, identity);
      final encoded = jsonEncode(encrypted);
      if (utf8.encode(encoded).length > _maxArchiveBytes) {
        throw StateError('The encrypted archive is larger than the 64 MB sync limit.');
      }
      _status = 'Saving encrypted backup to selected folder…';
      notifyListeners();
      await _channel.invokeMethod<void>(
        'writeBackup',
        {'treeUri': folderUri, 'contents': encoded},
      ).timeout(_timeout);
      _ensureIdentityActive(session, userId, identity);
      final now = DateTime.now();
      await _storage.write(
        key: _lastSyncKey(userId),
        value: '${now.millisecondsSinceEpoch}',
      );
      _lastSyncedAt = now;
      _status = 'Encrypted local backup updated.';
    } finally {
      _syncing = false;
      if (_activeUserId == session.userId) notifyListeners();
    }
  }

  void _ensureIdentityActive(
    ChatSession session,
    String userId,
    KeyPair identity,
  ) {
    if (session.userId != userId ||
        !identical(session.identity, identity) ||
        identity.hasBeenDestroyed) {
      throw StateError('The CrazeChat account changed or locked during local sync.');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
