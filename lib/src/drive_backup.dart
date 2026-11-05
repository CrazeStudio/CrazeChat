import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'crypto_service.dart';
import 'session.dart';

class GoogleDriveBackupService extends ChangeNotifier {
  GoogleDriveBackupService._();

  static final GoogleDriveBackupService instance = GoogleDriveBackupService._();
  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _filePrefix = 'crazechat-';
  static const _fileSuffix = '.encrypted-backup';
  static const _maxArchiveBytes = 64 * 1024 * 1024;
  static const _timeout = Duration(seconds: 45);
  static const _storage = FlutterSecureStorage();
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static final http.Client _client = http.Client();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _initializing;
  GoogleSignInAccount? _account;
  Future<void>? _activeSync;
  Timer? _debounce;
  ChatSession? _pendingSession;
  bool _syncAgain = false;
  String? _activeUserId;
  String? _accountEmail;
  DateTime? _lastSyncedAt;
  bool _enabled = false;
  bool _syncing = false;
  String? _status;

  bool get enabled => _enabled;
  bool get syncing => _syncing;
  String? get accountEmail => _accountEmail;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get status => _status;

  static String _enabledKey(String userId) => 'cc_drive_backup_enabled_$userId';
  static String _emailKey(String userId) => 'cc_drive_backup_email_$userId';
  static String _lastSyncKey(String userId) =>
      'cc_drive_backup_last_sync_$userId';

  Future<void> _initialize() {
    return _initializing ??= _googleSignIn.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
  }

  Future<void> refreshStatus(ChatSession session) async {
    final userId = session.userId;
    final accountChanged = _activeUserId != userId;
    _activeUserId = userId;
    if (accountChanged) _status = null;
    if (userId == null) {
      _enabled = false;
      _accountEmail = null;
      _lastSyncedAt = null;
      notifyListeners();
      return;
    }
    late final List<String?> values;
    try {
      values = await Future.wait([
        _storage.read(key: _enabledKey(userId)),
        _storage.read(key: _emailKey(userId)),
        _storage.read(key: _lastSyncKey(userId)),
      ]);
    } catch (_) {
      if (session.userId != userId) return;
      _enabled = false;
      _accountEmail = null;
      _lastSyncedAt = null;
      _status = 'Unable to read Drive backup settings from secure storage.';
      notifyListeners();
      return;
    }
    if (session.userId != userId) return;
    _enabled = values[0] == 'true';
    _accountEmail = values[1];
    final timestamp = int.tryParse(values[2] ?? '');
    _lastSyncedAt = timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    notifyListeners();
  }

  Future<void> connectAndSync(ChatSession session) async {
    await _runSync(session, interactive: true, bindAccount: true);
  }

  Future<void> syncNow(ChatSession session) async {
    if (!_enabled) throw StateError('Connect Google Drive backup first.');
    await _runSync(session, interactive: true, bindAccount: false);
  }

  Future<void> syncIfEnabled(ChatSession session) async {
    final userId = session.userId;
    if (userId == null || session.identity == null) return;
    if (await _storage.read(key: _enabledKey(userId)) != 'true' ||
        session.userId != userId)
      return;
    try {
      await _runSync(session, interactive: false, bindAccount: false);
    } catch (error) {
      _status = 'Automatic Drive sync needs attention: $error';
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

  Future<void> pauseSync(ChatSession session) async {
    final userId = session.userId;
    if (userId == null) return;
    await _storage.write(key: _enabledKey(userId), value: 'false');
    _enabled = false;
    _status = 'Automatic sync is paused. The existing encrypted Drive backup is unchanged.';
    notifyListeners();
  }

  Future<void> disconnect(ChatSession session) async {
    final userId = session.userId;
    if (userId != null) {
      await _storage.delete(key: _enabledKey(userId));
      await _storage.delete(key: _emailKey(userId));
      await _storage.delete(key: _lastSyncKey(userId));
    }
    _accountEmail = null;
    _enabled = false;
    _lastSyncedAt = null;
    _status = 'Google Drive disconnected. Its existing encrypted backup was not deleted.';
    try {
      await _initialize();
      await _googleSignIn.disconnect();
    } catch (_) {
      // Local sync is disabled even if Google sign-out is temporarily unavailable.
    }
    _account = null;
    notifyListeners();
  }

  Future<void> _runSync(
    ChatSession session, {
    required bool interactive,
    required bool bindAccount,
  }) async {
    if (_activeSync != null) {
      if (!interactive) _syncAgain = true;
      return _activeSync;
    }
    final task = _performSync(
      session,
      interactive: interactive,
      bindAccount: bindAccount,
    );
    _activeSync = task.whenComplete(() {
      _activeSync = null;
      if (_syncAgain) {
        _syncAgain = false;
        final pending = _pendingSession ?? session;
        _pendingSession = null;
        unawaited(syncIfEnabled(pending));
      }
    });
    return _activeSync!;
  }

  Future<void> _performSync(
    ChatSession session, {
    required bool interactive,
    required bool bindAccount,
  }) async {
    final userId = session.userId;
    final identity = session.identity;
    if (userId == null || identity == null) {
      throw StateError(
        'Unlock your CrazeChat identity before syncing encrypted messages.',
      );
    }
    _syncing = true;
    _activeUserId = userId;
    _status = 'Preparing encrypted backup…';
    notifyListeners();
    try {
      await _initialize();
      var account = _account;
      if (account == null) {
        final attempt = _googleSignIn.attemptLightweightAuthentication();
        if (attempt != null) {
          try {
            account = await attempt;
          } catch (_) {
            account = null;
          }
        }
      }
      if (account == null && interactive) {
        if (!_googleSignIn.supportsAuthenticate()) {
          throw UnsupportedError(
            'Google sign-in is not supported on this device.',
          );
        }
        account = await _googleSignIn.authenticate();
      }
      if (account == null) {
        _status = null;
        return;
      }
      _account = account;

      final boundEmail = await _storage.read(key: _emailKey(userId));
      if (!bindAccount && boundEmail != null && boundEmail != account.email) {
        throw StateError(
          'This CrazeChat account is linked to a different Google Drive account. Disconnect it before changing accounts.',
        );
      }
      if (!bindAccount && boundEmail == null) {
        throw StateError('Connect Google Drive backup before syncing.');
      }

      var authorization = await account.authorizationClient
          .authorizationForScopes([_scope]);
      if (authorization == null && interactive) {
        authorization = await account.authorizationClient.authorizeScopes([
          _scope,
        ]);
      }
      if (authorization == null) {
        _status = null;
        return;
      }
      final authHeaders = await account.authorizationClient
          .authorizationHeaders([_scope]);
      if (authHeaders == null || authHeaders['Authorization'] == null) {
        if (!interactive) {
          _status = null;
          return;
        }
        throw StateError(
          'Google did not provide Drive authorization. Try connecting again.',
        );
      }
      final headers = <String, String>{
        ...authHeaders,
        'Accept': 'application/json',
      };
      final fileName = await _fileNameForUser(userId);
      final fileId = await _findBackupFile(fileName, headers);

      if (fileId != null) {
        _status = 'Restoring encrypted messages…';
        notifyListeners();
        final remoteEnvelope = await _downloadBackup(fileId, headers);
        _ensureIdentityActive(session, userId, identity);
        final archiveBytes = await CryptoService.decryptDriveBackup(
          envelope: remoteEnvelope,
          identity: identity,
          userId: userId,
        );
        final decoded = jsonDecode(utf8.decode(archiveBytes));
        if (decoded is! Map)
          throw const FormatException('Drive backup archive is malformed.');
        await session.mergeEncryptedDriveArchive(
          Map<String, dynamic>.from(decoded),
        );
      }

      _ensureIdentityActive(session, userId, identity);
      _status = 'Encrypting messages…';
      notifyListeners();
      final archive = await session.exportEncryptedDriveArchive();
      final archiveBytes = utf8.encode(jsonEncode(archive));
      if (archiveBytes.length > _maxArchiveBytes) {
        throw StateError(
          'The encrypted archive is larger than the 64 MB sync limit.',
        );
      }
      final encrypted = await CryptoService.encryptDriveBackup(
        archiveBytes: archiveBytes,
        identity: identity,
        userId: userId,
      );
      _ensureIdentityActive(session, userId, identity);
      final encryptedBytes = utf8.encode(jsonEncode(encrypted));
      if (encryptedBytes.length > _maxArchiveBytes) {
        throw StateError(
          'The encrypted archive is larger than the 64 MB sync limit.',
        );
      }
      _status = 'Uploading encrypted backup…';
      notifyListeners();
      await _uploadBackup(fileId, fileName, encryptedBytes, headers);
      _ensureIdentityActive(session, userId, identity);

      if (bindAccount) {
        await _storage.write(key: _emailKey(userId), value: account.email);
      }
      await _storage.write(key: _enabledKey(userId), value: 'true');
      final now = DateTime.now();
      await _storage.write(
        key: _lastSyncKey(userId),
        value: '${now.millisecondsSinceEpoch}',
      );
      _enabled = true;
      _accountEmail = account.email;
      _lastSyncedAt = now;
      _status = 'Encrypted messages synced successfully.';
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
      throw StateError(
        'The CrazeChat account changed or locked during Drive sync.',
      );
    }
  }

  Future<String> _fileNameForUser(String userId) async {
    final digest = await Sha256().hash(utf8.encode(userId));
    final accountFingerprint = base64UrlEncode(digest.bytes)
        .replaceAll('=', '');
    return '$_filePrefix$accountFingerprint$_fileSuffix';
  }

  Future<String?> _findBackupFile(
    String fileName,
    Map<String, String> headers,
  ) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '$fileName' and trashed = false",
      'pageSize': '10',
      'fields': 'files(id,name,size,modifiedTime)',
    });
    final response = await _client.get(uri, headers: headers).timeout(_timeout);
    if (response.statusCode != 200) _throwDriveError(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['files'] is! List) return null;
    final files = (decoded['files'] as List).whereType<Map>().toList();
    if (files.isEmpty) return null;
    final size = int.tryParse(files.first['size']?.toString() ?? '');
    if (size != null && size > _maxArchiveBytes) {
      throw const FormatException(
        'The Drive backup is larger than the 64 MB sync limit.',
      );
    }
    final id = files.first['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<Map<String, dynamic>> _downloadBackup(
    String fileId,
    Map<String, String> headers,
  ) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
    });
    final request = http.Request('GET', uri)..headers.addAll(headers);
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode != 200) {
      _throwDriveError(
        await http.Response.fromStream(response).timeout(_timeout),
      );
    }
    if (response.contentLength != null &&
        response.contentLength! > _maxArchiveBytes) {
      final subscription = response.stream.listen((_) {}, onError: (_) {});
      await subscription.cancel();
      throw const FormatException(
        'The Drive backup is larger than the 64 MB sync limit.',
      );
    }
    final body = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(_timeout)) {
      received += chunk.length;
      if (received > _maxArchiveBytes) {
        throw const FormatException(
          'The Drive backup is larger than the 64 MB sync limit.',
        );
      }
      body.add(chunk);
    }
    final decoded = jsonDecode(utf8.decode(body.takeBytes()));
    if (decoded is! Map)
      throw const FormatException('Drive backup envelope is malformed.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _uploadBackup(
    String? fileId,
    String fileName,
    List<int> encryptedBytes,
    Map<String, String> headers,
  ) async {
    final isNew = fileId == null;
    final path = isNew
        ? '/upload/drive/v3/files'
        : '/upload/drive/v3/files/$fileId';
    final initiateUri = Uri.https('www.googleapis.com', path, {
      'uploadType': 'resumable',
    });
    final metadata = isNew
        ? jsonEncode({
            'name': fileName,
            'mimeType': 'application/json',
            'parents': ['appDataFolder'],
          })
        : '{}';
    final initiate = http.Request(isNew ? 'POST' : 'PATCH', initiateUri)
      ..headers.addAll(headers)
      ..headers['Content-Type'] = 'application/json; charset=UTF-8'
      ..headers['X-Upload-Content-Type'] = 'application/json'
      ..headers['X-Upload-Content-Length'] = '${encryptedBytes.length}'
      ..body = metadata;
    final initiateResponse = await http.Response.fromStream(
      await _client.send(initiate).timeout(_timeout),
    ).timeout(_timeout);
    if (initiateResponse.statusCode < 200 ||
        initiateResponse.statusCode >= 300) {
      _throwDriveError(initiateResponse);
    }
    final location = initiateResponse.headers['location'];
    if (location == null || location.isEmpty) {
      throw StateError('Google Drive did not start an upload session.');
    }
    final upload = http.Request('PUT', Uri.parse(location))
      ..headers.addAll(headers)
      ..headers['Content-Type'] = 'application/json'
      ..bodyBytes = encryptedBytes;
    final uploadResponse = await http.Response.fromStream(
      await _client.send(upload).timeout(_timeout),
    ).timeout(_timeout);
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      _throwDriveError(uploadResponse);
    }
  }

  Never _throwDriveError(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'Google Drive authorization failed. Reconnect Google Drive and try again.',
      );
    }
    throw StateError(
      'Google Drive request failed (HTTP ${response.statusCode}). Check Drive API setup and your connection.',
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
