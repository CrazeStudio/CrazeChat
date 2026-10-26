import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const defaultApiBaseUrl = String.fromEnvironment(
  'CRAZECHAT_API_BASE_URL',
  defaultValue: 'https://crazechat-api.vercel.app',
);

class ApiException implements Exception {
  const ApiException(this.status, this.message, {this.requestId = ''});
  final int status;
  final String message;
  final String requestId;

  @override
  String toString() => message;
}

Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry(key.toString(), value));
  return <String, dynamic>{};
}

String stringValue(Object? value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

class ApiClient {
  ApiClient({
    String? baseUrl,
    FlutterSecureStorage? storage,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? defaultApiBaseUrl).trim().replaceFirst(RegExp(r'/+$'), ''),
        storage = storage ?? const FlutterSecureStorage(),
        _http = client ?? http.Client();

  final String baseUrl;
  final FlutterSecureStorage storage;
  final http.Client _http;
  Future<bool>? _refreshFuture;

  static const _accessKey = 'crazechat.session.access';
  static const _refreshKey = 'crazechat.session.refresh';
  static const _uidKey = 'crazechat.session.uid';
  static const _usernameKey = 'crazechat.session.username';
  static const _themeKey = 'crazechat.ui.theme';

  Future<Map<String, String>?> readSession() async {
    final uid = await storage.read(key: _uidKey);
    final username = await storage.read(key: _usernameKey);
    final refresh = await storage.read(key: _refreshKey);
    if (uid == null || username == null || refresh == null) return null;
    return {
      'uid': uid,
      'username': username,
      'accessToken': await storage.read(key: _accessKey) ?? '',
      'refreshToken': refresh,
    };
  }

  Future<String> get themeMode async => await storage.read(key: _themeKey) ?? 'system';

  Future<void> setThemeMode(String mode) => storage.write(key: _themeKey, value: mode);

  Future<void> _persistAuth(Map<String, dynamic> response) async {
    final token = stringValue(response['token']);
    final refresh = stringValue(response['refreshToken']);
    final user = asJsonMap(response['user']);
    final uid = stringValue(user['userId']);
    final username = stringValue(user['username']);
    if (token.isEmpty || refresh.isEmpty || uid.isEmpty || username.isEmpty) {
      throw const ApiException(502, 'The API returned an incomplete sign-in session.');
    }
    await storage.write(key: _accessKey, value: token);
    await storage.write(key: _refreshKey, value: refresh);
    await storage.write(key: _uidKey, value: uid);
    await storage.write(key: _usernameKey, value: username);
  }

  Future<void> clearSession() async {
    await storage.delete(key: _accessKey);
    await storage.delete(key: _refreshKey);
    await storage.delete(key: _uidKey);
    await storage.delete(key: _usernameKey);
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    if (baseUrl.isEmpty) throw const ApiException(500, 'CrazeChat API base URL is empty.');
    final request = http.Request(method.toUpperCase(), _uri(path));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      final token = await storage.read(key: _accessKey);
      if (token == null || token.isEmpty) {
        throw const ApiException(401, 'Your session has expired. Please sign in again.');
      }
      request.headers['X-API-Token'] = token;
    }
    final streamed = await _http.send(request).timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> data;
    try {
      data = asJsonMap(jsonDecode(response.body));
    } catch (_) {
      data = <String, dynamic>{'error': response.body.trim().isEmpty ? 'The API returned an empty response.' : response.body.trim()};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        stringValue(data['error'], 'Request failed (HTTP ${response.statusCode}).'),
        requestId: stringValue(data['requestId']),
      );
    }
    return data;
  }

  bool _canRefreshPath(String path) {
    const noRefresh = {
      '/auth/register',
      '/auth/migrate',
      '/auth/login',
      '/api/user/login',
      '/auth/refresh',
      '/auth/logout',
      '/api/health',
      '/api/docs',
      '/',
    };
    return !noRefresh.contains(path);
  }

  Future<bool> _refreshSession() async {
    if (_refreshFuture != null) return _refreshFuture!;
    _refreshFuture = () async {
      final refresh = await storage.read(key: _refreshKey);
      if (refresh == null || refresh.isEmpty) return false;
      try {
        final response = await _send(
          'POST',
          '/auth/refresh',
          body: {'refreshToken': refresh},
          authenticated: false,
        );
        await _persistAuth(response);
        return true;
      } on ApiException catch (error) {
        // Preserve refresh credentials during temporary backend outages or rate limits.
        if (error.status == 401) await clearSession();
        return false;
      } catch (_) {
        return false;
      }
    }();
    try {
      return await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    bool retryAfterRefresh = true,
  }) async {
    try {
      return await _send(method, path, body: body, authenticated: authenticated);
    } on ApiException catch (error) {
      if (error.status == 401 &&
          authenticated &&
          retryAfterRefresh &&
          _canRefreshPath(path)) {
        final refreshed = await _refreshSession();
        if (refreshed) {
          return request(method, path, body: body, authenticated: true, retryAfterRefresh: false);
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> health() => request('GET', '/api/health', authenticated: false);
  Future<Map<String, dynamic>> docs() => request('GET', '/api/docs', authenticated: false);
  Future<Map<String, dynamic>> verifyRetiredRoute() => request('GET', '/verify', authenticated: false);

  Future<Map<String, dynamic>> register(String username, String password) async {
    final result = await request('POST', '/auth/register', body: {
      'username': username.trim(),
      'password': password,
    }, authenticated: false);
    await _persistAuth(result);
    return result;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    Map<String, dynamic> result;
    try {
      result = await request('POST', '/api/user/login', body: {
        'username': username.trim(),
        'password': password,
      }, authenticated: false);
    } on ApiException catch (error) {
      if (error.status == 404) {
        result = await request('POST', '/auth/login', body: {
          'username': username.trim(),
          'password': password,
        }, authenticated: false);
      } else if (error.status == 401) {
        try {
          result = await request('POST', '/auth/migrate', body: {
            'username': username.trim(),
            'password': password,
          }, authenticated: false);
        } on ApiException catch (migrationError) {
          if (migrationError.status == 404 || migrationError.status == 401) {
            throw const ApiException(401, 'Could not sign in. Check your username and password. Older accounts may need their original encrypted profile backup.');
          }
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    await _persistAuth(result);
    return result;
  }

  Future<void> logout() async {
    final refresh = await storage.read(key: _refreshKey);
    try {
      await request('POST', '/auth/logout', body: {'refreshToken': refresh ?? ''}, authenticated: false);
    } finally {
      await clearSession();
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String encryptedBackup,
    required String publicKey,
  }) => request('POST', '/auth/change-password', body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'encryptedBackup': encryptedBackup,
        'publicKey': publicKey,
      });

  Future<Map<String, dynamic>> deleteAccount(String password) =>
      request('DELETE', '/auth/account', body: {'password': password});

  Future<Map<String, dynamic>> getMyProfile() => request('GET', '/api/chat/users/me');

  Future<Map<String, dynamic>> updateMyProfile({
    required String publicKey,
    String? pfpUrl,
  }) => request('PUT', '/api/chat/users/me', body: {
        'publicKey': publicKey,
        if (pfpUrl != null) 'pfpUrl': pfpUrl,
      });

  Future<Map<String, dynamic>> patchMyProfile({
    String? pfpUrl,
    String? publicKey,
  }) => request('PATCH', '/api/chat/users/me', body: {
        if (pfpUrl != null) 'pfpUrl': pfpUrl,
        if (publicKey != null) 'publicKey': publicKey,
      });

  Future<Map<String, dynamic>> getUser(String userId) =>
      request('GET', '/api/chat/users/${Uri.encodeComponent(userId)}');

  Future<Map<String, dynamic>> getUserByUsername(String username) =>
      request('GET', '/api/chat/users/by-username/${Uri.encodeComponent(username)}');

  Future<List<Map<String, dynamic>>> getUsers() async =>
      (asJsonMap(await request('GET', '/api/chat/users'))['users'] as List? ?? const [])
          .map(asJsonMap)
          .toList();

  Future<Map<String, dynamic>> getPrivacy() => request('GET', '/api/chat/privacy/me');

  Future<Map<String, dynamic>> updatePrivacy(Map<String, bool> patch) =>
      request('PATCH', '/api/chat/privacy/me', body: patch);

  Future<List<Map<String, dynamic>>> getChats() async =>
      (asJsonMap(await request('GET', '/api/chat/chats'))['chats'] as List? ?? const [])
          .map(asJsonMap)
          .toList();

  Future<Map<String, dynamic>> getChat(String chatId) =>
      request('GET', '/api/chat/chats/${Uri.encodeComponent(chatId)}');

  Future<Map<String, dynamic>> createChat({
    required List<String> memberIds,
    required String title,
    required bool isGroup,
  }) => request('POST', '/api/chat/chats', body: {
        'memberIds': memberIds,
        'title': title,
        'isGroup': isGroup,
      });

  Future<Map<String, dynamic>> addGroupMember(String chatId, String memberId) =>
      request('POST', '/api/chat/chats/${Uri.encodeComponent(chatId)}/members', body: {'memberId': memberId});

  Future<Map<String, dynamic>> rotateGroupKeys(
    String chatId, {
    required String ownerPublicKey,
    required Map<String, Map<String, String>> envelopes,
  }) => request('PUT', '/api/chat/chats/${Uri.encodeComponent(chatId)}/group-keys', body: {
        'ownerPublicKey': ownerPublicKey,
        'envelopes': envelopes,
      });

  Future<Map<String, dynamic>> getMyGroupKey(String chatId, {int? version}) {
    final query = version == null ? '' : '?version=$version';
    return request('GET', '/api/chat/chats/${Uri.encodeComponent(chatId)}/group-key/me$query');
  }

  Future<List<Map<String, dynamic>>> getMessages(String chatId, {int limit = 50, DateTime? before}) async {
    final params = <String, String>{'chatId': chatId, 'limit': '$limit'};
    if (before != null) params['before'] = before.toUtc().toIso8601String();
    final path = Uri(path: '/api/chat/messages', queryParameters: params).toString();
    return (asJsonMap(await request('GET', path))['messages'] as List? ?? const [])
        .map(asJsonMap)
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String ciphertext,
    required String nonce,
    required int ttlMinutes,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    String? receiverId,
  }) => request('POST', '/api/chat/messages', body: {
        'chatId': chatId,
        'ciphertext': ciphertext,
        'nonce': nonce,
        'ttlMinutes': ttlMinutes,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToText != null && replyToText.isNotEmpty) 'replyToText': replyToText,
        if (replyToSender != null && replyToSender.isNotEmpty) 'replyToSender': replyToSender,
        if (receiverId != null && receiverId.isNotEmpty) 'receiverId': receiverId,
      });

  Future<Map<String, dynamic>> markSeen(String messageId) =>
      request('POST', '/api/chat/messages/${Uri.encodeComponent(messageId)}/seen', body: {});

  Future<Map<String, dynamic>> getSeen(String messageId) =>
      request('GET', '/api/chat/messages/${Uri.encodeComponent(messageId)}/seen');

  Future<Map<String, dynamic>> editMessage(String messageId, String ciphertext, String nonce) =>
      request('PATCH', '/api/chat/messages/${Uri.encodeComponent(messageId)}', body: {
        'ciphertext': ciphertext,
        'nonce': nonce,
      });

  Future<Map<String, dynamic>> deleteMessage(String messageId) =>
      request('DELETE', '/api/chat/messages/${Uri.encodeComponent(messageId)}');

  Future<Map<String, dynamic>> pinMessage(String messageId, bool pinned) =>
      request('POST', '/api/chat/messages/${Uri.encodeComponent(messageId)}/pin', body: {'pinned': pinned});

  Future<Map<String, dynamic>> reactToMessage(String messageId, String emoji) =>
      request('POST', '/api/chat/messages/${Uri.encodeComponent(messageId)}/reactions', body: {'emoji': emoji});

  Future<Map<String, dynamic>> removeReaction(String messageId) =>
      request('DELETE', '/api/chat/messages/${Uri.encodeComponent(messageId)}/reactions');

  Future<Map<String, dynamic>> setPresence(bool online) =>
      request('POST', '/api/chat/presence', body: {'isOnline': online});

  Future<List<Map<String, dynamic>>> getPresence(List<String> uids) async {
    if (uids.isEmpty) return [];
    final query = Uri(path: '/api/chat/presence', queryParameters: {'uids': uids.toSet().take(100).join(',')}).toString();
    return (asJsonMap(await request('GET', query))['presence'] as List? ?? const [])
        .map(asJsonMap)
        .toList();
  }

  Future<Map<String, dynamic>> putMyKey(String publicKey, {String keyId = 'p256-v1'}) =>
      request('PUT', '/api/chat/keys/me', body: {'publicKey': publicKey, 'keyId': keyId});

  Future<List<Map<String, dynamic>>> getKeys(List<String> uids) async {
    if (uids.isEmpty) return [];
    final query = Uri(path: '/api/chat/keys', queryParameters: {'uids': uids.toSet().take(100).join(',')}).toString();
    return (asJsonMap(await request('GET', query))['keys'] as List? ?? const [])
        .map(asJsonMap)
        .toList();
  }

  Future<Map<String, dynamic>> putBackup(String ciphertext, String nonce) =>
      request('PUT', '/api/chat/backups/me', body: {'ciphertext': ciphertext, 'nonce': nonce});

  Future<Map<String, dynamic>> getBackup() => request('GET', '/api/chat/backups/me');

  Future<Map<String, dynamic>> deleteBackup() => request('DELETE', '/api/chat/backups/me');

  void close() => _http.close();
}

class ChatMessage {
  ChatMessage.fromJson(Map<String, dynamic> json)
      : id = stringValue(json['id']),
        chatId = stringValue(json['chatId']),
        senderUid = stringValue(json['senderUid'], stringValue(json['senderId'])),
        senderUsername = stringValue(json['senderUsername']),
        receiverId = stringValue(json['receiverId']),
        ciphertext = stringValue(json['ciphertext']),
        nonce = stringValue(json['nonce']),
        replyToId = stringValue(json['replyToId']),
        replyToText = stringValue(json['replyToText']),
        replyToSender = stringValue(json['replyToSender']),
        createdAt = DateTime.tryParse(stringValue(json['createdAt'])) ??
            DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num?)?.toInt() ?? 0),
        expiresAt = DateTime.tryParse(stringValue(json['expiresAt'])),
        editedAt = DateTime.tryParse(stringValue(json['editedAt'])),
        pinned = json['pinned'] == true || json['isPinned'] == true,
        isDeleted = json['isDeleted'] == true,
        reactions = asJsonMap(json['reactions']).map((key, value) => MapEntry(key, stringValue(value))),
        receipts = asJsonMap(json['receipts']).map((key, value) => MapEntry(key, asJsonMap(value)));

  final String id;
  final String chatId;
  final String senderUid;
  final String senderUsername;
  final String receiverId;
  final String ciphertext;
  final String nonce;
  final String replyToId;
  final String replyToText;
  final String replyToSender;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? editedAt;
  final bool pinned;
  final bool isDeleted;
  final Map<String, String> reactions;
  final Map<String, Map<String, dynamic>> receipts;
}

class UserProfile {
  UserProfile.fromJson(Map<String, dynamic> json)
      : userId = stringValue(json['userId'], stringValue(json['uid'])),
        username = stringValue(json['username']),
        publicKey = stringValue(json['publicKey']).split('::ENC::').first,
        pfpUrl = stringValue(json['pfpUrl']),
        privacy = asJsonMap(json['privacy']).map((k, v) => MapEntry(k, v == true));

  final String userId;
  final String username;
  final String publicKey;
  final String pfpUrl;
  final Map<String, bool> privacy;
}

class ChatRecord {
  ChatRecord.fromJson(Map<String, dynamic> json)
      : id = stringValue(json['id'], stringValue(json['chatId'])),
        title = stringValue(json['title'], stringValue(json['groupName'])),
        isGroup = json['isGroup'] == true || json['isGroup'] == 'true',
        createdBy = stringValue(json['createdBy'], stringValue(json['groupOwnerId'])),
        createdAt = DateTime.tryParse(stringValue(json['createdAt'])) ??
            DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num?)?.toInt() ?? 0),
        groupKeyVersion = (json['groupKeyVersion'] as num?)?.toInt() ?? 0,
        pinnedMessageId = stringValue(json['pinnedMessageId']),
        memberIds = ((json['memberIds'] as List?) ??
                (json['members'] is Map ? (json['members'] as Map).keys.toList() : const []))
            .map((value) => value.toString())
            .toList();

  final String id;
  final String title;
  final bool isGroup;
  final String createdBy;
  final DateTime createdAt;
  final int groupKeyVersion;
  final String pinnedMessageId;
  final List<String> memberIds;
}

class CryptoService {
  CryptoService({FlutterSecureStorage? storage}) : storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage storage;
  final Ecdh _ecdh = Ecdh.p256(length: 32);
  final AesGcm _aes = AesGcm.with256bits();
  final Sha256 _sha256 = Sha256();

  String _privateName(String uid) => 'crazechat.identity.$uid.private';
  String _xName(String uid) => 'crazechat.identity.$uid.x';
  String _yName(String uid) => 'crazechat.identity.$uid.y';
  String _publicName(String uid) => 'crazechat.identity.$uid.public';
  String _groupName(String uid, String chatId, int version) => 'crazechat.group.$uid.$chatId.$version';

  Uint8List _decode64(String value) {
    final clean = value.trim();
    try {
      return Uint8List.fromList(base64Decode(clean));
    } catch (_) {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(clean)));
    }
  }

  String _b64(List<int> bytes) => base64Encode(bytes);

  List<int> _parsePublicPoint(String publicKeyBase64) {
    final der = _decode64(publicKeyBase64);
    if (der.length < 65) throw const FormatException('Public key is too short.');
    final offset = der.length - 65;
    if (der[offset] != 0x04) throw const FormatException('Public key is not an uncompressed P-256 point.');
    return der.sublist(offset + 1);
  }

  List<int> _parsePrivateScalar(String privateKeyBase64) {
    final der = _decode64(privateKeyBase64);
    for (var i = 0; i < der.length - 33; i++) {
      if (der[i] == 0x04 && der[i + 1] == 0x20) {
        final scalar = der.sublist(i + 2, i + 34);
        if (scalar.length == 32) return scalar;
      }
    }
    throw const FormatException('Unsupported private-key encoding.');
  }

  List<int> _pkcs8(List<int> d) {
    const prefix = <int>[
      0x30, 0x4d, 0x02, 0x01, 0x00, 0x30, 0x13,
      0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
      0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
      0x04, 0x33, 0x30, 0x31, 0x02, 0x01, 0x01, 0x04, 0x20,
    ];
    const suffix = <int>[
      0xa0, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
    ];
    return <int>[...prefix, ...d, ...suffix];
  }

  Future<void> _saveKeyMaterial(String uid, String publicKey, String privateKey) async {
    final xy = _parsePublicPoint(publicKey);
    final d = _parsePrivateScalar(privateKey);
    await storage.write(key: _privateName(uid), value: base64Encode(d));
    await storage.write(key: _xName(uid), value: base64Encode(xy.sublist(0, 32)));
    await storage.write(key: _yName(uid), value: base64Encode(xy.sublist(32, 64)));
    await storage.write(key: _publicName(uid), value: publicKey);
  }

  Future<EcKeyPairData?> _localPair(String uid) async {
    final d = await storage.read(key: _privateName(uid));
    final x = await storage.read(key: _xName(uid));
    final y = await storage.read(key: _yName(uid));
    if (d == null || x == null || y == null) return null;
    return EcKeyPairData(
      d: _decode64(d),
      x: _decode64(x),
      y: _decode64(y),
      type: KeyPairType.p256,
    );
  }

  Future<String?> localPublicKey(String uid) => storage.read(key: _publicName(uid));

  Future<void> ensureIdentity({
    required String uid,
    required String username,
    required String password,
    required ApiClient api,
  }) async {
    var pair = await _localPair(uid);
    if (pair != null) {
      final localPublic = await localPublicKey(uid);
      final profileResponse = await api.getMyProfile();
      final profile = asJsonMap(profileResponse['user']);
      final remoteRaw = stringValue(profile['publicKey']);
      final remotePublic = remoteRaw.split('::ENC::').first;
      final remoteBackup = stringValue(profile['encryptedBackup']);
      if (remotePublic.isEmpty || remotePublic != localPublic) {
        final backup = remoteBackup.isNotEmpty ? remoteBackup : _backupFromRaw(remoteRaw);
        if (backup.isNotEmpty && backup.startsWith('CCP2:')) {
          // Preserve the identity already registered remotely instead of silently replacing it.
          final restored = await _tryRestore(backup, password, uid, username);
          if (restored != null) {
            await _saveKeyMaterial(uid, restored['publicKey']!, restored['privateKey']!);
            pair = await _localPair(uid);
          } else if (remotePublic.isNotEmpty) {
            throw StateError('This account has a different encrypted identity key. Restore its backup on the original device; this app will not overwrite it.');
          }
        } else if (remotePublic.isNotEmpty) {
          throw StateError('The account has an encryption key but no usable backup. Keep the original device and its app data; do not uninstall or reset it.');
        }
      }
      if (pair != null) {
        await _ensureBackupIfMissing(uid, username, password, api, profile, localPublic!);
        return;
      }
    }

    final profileResponse = await api.getMyProfile();
    final profile = asJsonMap(profileResponse['user']);
    final rawPublic = stringValue(profile['publicKey']);
    final remotePublic = rawPublic.split('::ENC::').first;
    var backup = stringValue(profile['encryptedBackup']);
    if (backup.isEmpty) backup = _backupFromRaw(rawPublic);
    if (backup.isEmpty) {
      try {
        final mirrored = asJsonMap((await api.getBackup())['backup']);
        backup = stringValue(mirrored['ciphertext']);
      } on ApiException catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    if (backup.startsWith('CCP2:')) {
      final restored = await _tryRestore(backup, password, uid, username);
      if (restored != null) {
        await _saveKeyMaterial(uid, restored['publicKey']!, restored['privateKey']!);
        return;
      }
      if (remotePublic.isNotEmpty) {
        throw StateError('The encrypted profile backup could not be opened with this password. Keep your original device and app data.');
      }
    } else if (remotePublic.isNotEmpty) {
      throw StateError('This account has a registered encryption key but no password-recoverable backup. Do not create a new key or delete the original app data.');
    }

    final generated = await _ecdh.newKeyPair();
    final data = await generated.extract();
    final publicKey = _b64(data.publicKey.toDer());
    final privateKey = _b64(_pkcs8(data.d));
    await _saveKeyMaterial(uid, publicKey, privateKey);
    await syncIdentity(uid: uid, username: username, password: password, api: api, forceBackup: true);
    await api.putMyKey(publicKey);
  }

  String _backupFromRaw(String raw) {
    final parts = raw.split('::ENC::');
    return parts.length > 1 ? parts.sublist(1).join('::ENC::') : '';
  }

  Future<Map<String, String>?> _tryRestore(
    String backup,
    String password,
    String uid,
    String username,
  ) async {
    final plain = await decryptProfileBackup(backup, password, username);
    if (plain == null) return null;
    try {
      final json = asJsonMap(jsonDecode(plain));
      final backupUid = stringValue(json['uid'], stringValue(json['userId']));
      final backupUser = stringValue(json['username']);
      final publicKey = stringValue(json['publicKeyBase64'], stringValue(json['publicKey']));
      final privateKey = stringValue(json['privateKeyBase64'], stringValue(json['privateKey']));
      if (backupUid == uid && backupUser.toLowerCase() == username.toLowerCase() && publicKey.isNotEmpty && privateKey.isNotEmpty) {
        return {'publicKey': publicKey, 'privateKey': privateKey};
      }
    } catch (_) {
      final parts = plain.split('|');
      if (parts.length >= 5 && parts[0] == uid && parts[1].toLowerCase() == username.toLowerCase()) {
        final publicKey = parts[3];
        final privateKey = parts[4];
        if (publicKey.isNotEmpty && privateKey.isNotEmpty) {
          _parsePublicPoint(publicKey);
          _parsePrivateScalar(privateKey);
          return {'publicKey': publicKey, 'privateKey': privateKey};
        }
      }
    }
    return null;
  }

  Future<String?> decryptProfileBackup(String backup, String password, String username) async {
    try {
      if (backup.startsWith('CCP2:')) {
        final packed = _decode64(backup.substring(5));
        if (packed.length < 44) return null;
        final salt = packed.sublist(0, 16);
        final nonce = packed.sublist(16, 28);
        final encrypted = packed.sublist(28);
        final key = await Pbkdf2.hmacSha256(iterations: 600000, bits: 256)
            .deriveKeyFromPassword(password: password, nonce: salt);
        final box = SecretBox(
          encrypted.sublist(0, encrypted.length - 16),
          nonce: nonce,
          mac: Mac(encrypted.sublist(encrypted.length - 16)),
        );
        return utf8.decode(await _aes.decrypt(box, secretKey: key, aad: utf8.encode('CrazeChatProfileV2')));
      }
      final packed = _decode64(backup);
      if (packed.length < 28) return null;
      final nonce = packed.sublist(0, 12);
      final encrypted = packed.sublist(12);
      final salt = utf8.encode('CrazeChat_PBKDF2_Salt_2026_${username.toLowerCase()}');
      final key = await Pbkdf2.hmacSha256(iterations: 2000, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);
      final box = SecretBox(
        encrypted.sublist(0, encrypted.length - 16),
        nonce: nonce,
        mac: Mac(encrypted.sublist(encrypted.length - 16)),
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureBackupIfMissing(
    String uid,
    String username,
    String password,
    ApiClient api,
    Map<String, dynamic> profile,
    String publicKey,
  ) async {
    var backup = stringValue(profile['encryptedBackup']);
    if (backup.isEmpty) backup = _backupFromRaw(stringValue(profile['publicKey']));
    if (backup.isNotEmpty && backup.startsWith('CCP2:')) {
      try {
        await api.putBackup(backup, 'CrazeChatProfileBackupCCP2');
        return;
      } on ApiException catch (e) {
        if (e.status != 401) rethrow;
      }
    }
    await syncIdentity(uid: uid, username: username, password: password, api: api, forceBackup: true);
  }

  Future<String> makePasswordBackup(String uid, String username, String password) async {
    final pair = await _localPair(uid);
    final publicKey = await localPublicKey(uid);
    if (pair == null || publicKey == null) throw StateError('This device does not have the private key for this account.');
    final privateKey = await _privateKeyPkcs8(uid);
    final plaintext = '$uid|$username||$publicKey|$privateKey';
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final key = await Pbkdf2.hmacSha256(iterations: 600000, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: key, nonce: nonce, aad: utf8.encode('CrazeChatProfileV2'));
    final packed = <int>[...salt, ...nonce, ...box.cipherText, ...box.mac.bytes];
    return 'CCP2:${base64Encode(packed)}';
  }

  Future<String> _privateKeyPkcs8(String uid) async {
    final d = await storage.read(key: _privateName(uid));
    if (d == null) throw StateError('Private key missing.');
    return _b64(_pkcs8(_decode64(d)));
  }

  Future<void> syncIdentity({
    required String uid,
    required String username,
    required String password,
    required ApiClient api,
    bool forceBackup = false,
  }) async {
    final pair = await _localPair(uid);
    final publicKey = await localPublicKey(uid);
    if (pair == null || publicKey == null) throw StateError('Profile keys are unavailable.');
    String? backup;
    if (forceBackup) {
      backup = await makePasswordBackup(uid, username, password);
    } else {
      final profile = asJsonMap((await api.getMyProfile())['user']);
      backup = stringValue(profile['encryptedBackup']);
      if (backup.isEmpty) backup = _backupFromRaw(stringValue(profile['publicKey']));
      if (backup.isEmpty || !backup.startsWith('CCP2:')) {
        backup = await makePasswordBackup(uid, username, password);
      }
    }
    await api.updateMyProfile(publicKey: '$publicKey::ENC::$backup');
    await api.putBackup(backup, 'CrazeChatProfileBackupCCP2');
    await api.putMyKey(publicKey);
  }

  Future<EcKeyPairData> _requirePair(String uid) async {
    final pair = await _localPair(uid);
    if (pair == null) throw StateError('This device does not have the private key for this account. Restore the encrypted backup first.');
    return pair;
  }

  Future<String> _deriveAesKey(String uid, String remotePublicKey) async {
    final pair = await _requirePair(uid);
    final remote = _parsePublicPoint(remotePublicKey);
    final remotePublic = EcPublicKey(
      x: remote.sublist(0, 32),
      y: remote.sublist(32, 64),
      type: KeyPairType.p256,
    );
    final secret = await _ecdh.sharedSecretKey(keyPair: pair, remotePublicKey: remotePublic);
    final secretBytes = await secret.extractBytes();
    final digest = await _sha256.hash(secretBytes);
    return base64Encode(digest.bytes);
  }

  Future<SecretKey> _directSecret(String uid, String remotePublicKey) async =>
      SecretKey(_decode64(await _deriveAesKey(uid, remotePublicKey)));

  Future<Map<String, String>> encryptDirect(
    String uid,
    String remotePublicKey,
    String plaintext,
  ) async {
    final key = await _directSecret(uid, remotePublicKey);
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: key);
    return {'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]), 'nonce': base64Encode(box.nonce)};
  }

  Future<String> decryptDirect(
    String uid,
    String remotePublicKey,
    String ciphertext,
    String nonce,
  ) async {
    final key = await _directSecret(uid, remotePublicKey);
    final raw = _decode64(ciphertext);
    if (raw.length < 16) throw const FormatException('Ciphertext is too short.');
    final iv = _decode64(nonce);
    final box = SecretBox(raw.sublist(0, raw.length - 16), nonce: iv, mac: Mac(raw.sublist(raw.length - 16)));
    return utf8.decode(await _aes.decrypt(box, secretKey: key));
  }

  Future<String> _sharedAesKey(String uid, String remotePublicKey) async =>
      _deriveAesKey(uid, remotePublicKey);

  Future<Map<String, String>> _encryptGroupKeyForMember(
    String uid,
    String remotePublicKey,
    String keyBase64,
  ) async {
    final key = SecretKey(_decode64(await _sharedAesKey(uid, remotePublicKey)));
    final box = await _aes.encrypt(utf8.encode(keyBase64), secretKey: key);
    return {'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]), 'nonce': base64Encode(box.nonce)};
  }

  Future<String> rotateGroupKey({
    required String uid,
    required String username,
    required ApiClient api,
    required ChatRecord chat,
  }) async {
    final localPublic = await localPublicKey(uid);
    if (localPublic == null) throw StateError('Your encryption identity is missing.');
    if (chat.createdBy != uid) throw StateError('Only the group owner can rotate the group key.');
    final groupBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final groupKey = base64Encode(groupBytes);
    final envelopes = <String, Map<String, String>>{};
    for (final memberId in chat.memberIds) {
      final memberResponse = memberId == uid ? await api.getMyProfile() : await api.getUser(memberId);
      final profile = asJsonMap(memberResponse['user']);
      final publicKey = stringValue(profile['publicKey']).split('::ENC::').first;
      if (publicKey.isEmpty) throw StateError('A group member has no public encryption key. Ask them to sign in and sync their profile.');
      envelopes[memberId] = await _encryptGroupKeyForMember(uid, publicKey, groupKey);
    }
    final result = await api.rotateGroupKeys(chat.id, ownerPublicKey: localPublic, envelopes: envelopes);
    final version = (result['version'] as num?)?.toInt() ?? 0;
    if (version < 1) throw StateError('The API did not return a group key version.');
    await storage.write(key: _groupName(uid, chat.id, version), value: groupKey);
    return groupKey;
  }

  int groupMessageVersion(String ciphertext) {
    final match = RegExp(r'^G2v([1-9][0-9]{0,8}):').firstMatch(ciphertext);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<String> _loadGroupKey({
    required String uid,
    required ApiClient api,
    required String chatId,
    required int version,
  }) async {
    final saved = await storage.read(key: _groupName(uid, chatId, version));
    if (saved != null && saved.isNotEmpty) return saved;
    final response = asJsonMap((await api.getMyGroupKey(chatId, version: version))['envelope']);
    final ownerPublic = stringValue(response['ownerPublicKey']);
    final encrypted = stringValue(response['ciphertext']);
    final nonce = stringValue(response['nonce']);
    if (ownerPublic.isEmpty || encrypted.isEmpty || nonce.isEmpty) {
      throw StateError('No encrypted group key is available for version $version.');
    }
    final key = SecretKey(_decode64(await _sharedAesKey(uid, ownerPublic)));
    final raw = _decode64(encrypted);
    if (raw.length < 16) throw const FormatException('Invalid group-key envelope.');
    final box = SecretBox(raw.sublist(0, raw.length - 16), nonce: _decode64(nonce), mac: Mac(raw.sublist(raw.length - 16)));
    final groupKey = utf8.decode(await _aes.decrypt(box, secretKey: key));
    if (_decode64(groupKey).length != 32) throw const FormatException('Invalid group secret.');
    await storage.write(key: _groupName(uid, chatId, version), value: groupKey);
    return groupKey;
  }

  Future<Map<String, String>> encryptGroup({
    required String uid,
    required ApiClient api,
    required String chatId,
    required int version,
    required String plaintext,
  }) async {
    final groupKey = await _loadGroupKey(uid: uid, api: api, chatId: chatId, version: version);
    final rawKey = _decode64(groupKey);
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: SecretKey(rawKey), nonce: nonce, aad: utf8.encode('CrazeChatGroupV2:$version'));
    return {
      'ciphertext': 'G2v$version:${base64Encode([...box.cipherText, ...box.mac.bytes])}',
      'nonce': base64Encode(nonce),
    };
  }

  Future<String> decryptGroup({
    required String uid,
    required ApiClient api,
    required String chatId,
    required String ciphertext,
    required String nonce,
  }) async {
    final version = groupMessageVersion(ciphertext);
    if (version < 1) throw StateError('Legacy group message has no versioned encryption key.');
    final groupKey = await _loadGroupKey(uid: uid, api: api, chatId: chatId, version: version);
    final encoded = ciphertext.substring(ciphertext.indexOf(':') + 1);
    final raw = _decode64(encoded);
    if (raw.length < 16) throw const FormatException('Group ciphertext is too short.');
    final box = SecretBox(raw.sublist(0, raw.length - 16), nonce: _decode64(nonce), mac: Mac(raw.sublist(raw.length - 16)));
    return utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(_decode64(groupKey)), aad: utf8.encode('CrazeChatGroupV2:$version')));
  }

  Future<bool> hasIdentity(String uid) async =>
      (await storage.read(key: _privateName(uid))) != null &&
      (await localPublicKey(uid)) != null;

  /// Backward-compatible reader for messages from the old version that used a
  /// static, app-embedded group key. New messages must use versioned group keys.
  Future<String> decryptLegacyGroup(String chatId, String ciphertext, String nonce) async {
    try {
      if (ciphertext.isEmpty || nonce.isEmpty) return '';
      final digest = await _sha256.hash(
        utf8.encode('CrazeChat_Group_Secret_Key_2026_$chatId'),
      );
      final raw = _decode64(ciphertext);
      if (raw.length < 16) return '[Legacy Encrypted Group Message]';
      final box = SecretBox(
        raw.sublist(0, raw.length - 16),
        nonce: _decode64(nonce),
        mac: Mac(raw.sublist(raw.length - 16)),
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(digest.bytes)));
    } catch (_) {
      return '[Legacy Encrypted Group Message]';
    }
  }

  Future<void> deleteIdentity(String uid) async {
    await storage.delete(key: _privateName(uid));
    await storage.delete(key: _xName(uid));
    await storage.delete(key: _yName(uid));
    await storage.delete(key: _publicName(uid));
    final all = await storage.readAll();
    for (final key in all.keys.where((key) => key.startsWith('crazechat.group.$uid.'))) {
      await storage.delete(key: key);
    }
  }
}
