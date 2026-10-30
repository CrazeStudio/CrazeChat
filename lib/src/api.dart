import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class CrazeChatApi {
  CrazeChatApi({this.token});
  static const baseUrl = String.fromEnvironment('BURL');
  static const accessKey = String.fromEnvironment('KEY');
  static final _passwordKdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 310000, bits: 256);
  String? token;

  Future<Map<String, dynamic>> get(String path) async {
    if (path == '/chats') return _listChats();
    final match = RegExp(r'^/chats/([a-f0-9]{32})/messages$').firstMatch(path);
    if (match != null) return _listMessages(match.group(1)!);
    throw const ApiException('This CrazeChat API operation is not supported.', statusCode: 404);
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) async {
    final data = body ?? const <String, dynamic>{};
    if (path == '/auth/register') return _register(data);
    if (path == '/auth/login') return _login(data);
    if (path == '/chats') return _createChat(data);
    final match = RegExp(r'^/chats/([a-f0-9]{32})/messages$').firstMatch(path);
    if (match != null) return _sendMessage(match.group(1)!, data);
    throw const ApiException('This CrazeChat API operation is not supported.', statusCode: 404);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final match = RegExp(r'^/chats/([a-f0-9]{32})/messages/([a-f0-9]{32})$').firstMatch(path);
    if (match == null) throw const ApiException('This CrazeChat delete operation is not supported.', statusCode: 404);
    final identity = _requireIdentity();
    final chatId = match.group(1)!;
    final messageId = match.group(2)!;
    await _requireChatMember(chatId, identity.uid);
    final message = await _dbGet('Massages/$chatId/$messageId');
    if (message is! Map || message['senderId'] != identity.uid) {
      throw const ApiException('You can only delete messages you sent.', statusCode: 403);
    }
    await _dbDelete('Massages/$chatId/$messageId');
    return {'ok': true, 'deleted': messageId};
  }

  Future<Map<String, dynamic>> _register(Map<String, dynamic> data) async {
    final username = data['username'];
    final password = data['password'];
    final publicKey = data['publicKey'];
    final envelope = data['identityEnvelope'];
    if (username is! String || !_validUsername(username)) {
      throw const ApiException('Username must be 3–20 letters, numbers, or underscores.', statusCode: 400);
    }
    if (password is! String || password.length < 12 || password.length > 256) {
      throw const ApiException('Use a password with at least 12 characters.', statusCode: 400);
    }
    if (publicKey is! String || envelope is! Map || envelope['publicKey'] != publicKey) {
      throw const ApiException('A valid encrypted identity key is required.', statusCode: 400);
    }

    final normalized = username.toLowerCase();
    if (await _dbGet('usernames/$normalized') != null) {
      throw const ApiException('That username is already taken.', statusCode: 409);
    }

    final uid = _randomHex(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final user = <String, dynamic>{
      'uid': uid,
      'username': username,
      'usernameLower': normalized,
      'passwordHash': await _hashPassword(password),
      'publicKey': publicKey,
      'identityEnvelope': Map<String, dynamic>.from(envelope),
      'createdAt': now,
    };

    await _dbPut('usernames/$normalized', {'uid': uid});
    try {
      await _dbPut('users/$uid', user);
    } catch (_) {
      await _dbDelete('usernames/$normalized');
      rethrow;
    }
    return {
      'token': _makeLocalSessionToken(uid, username),
      'user': _safeUser(user),
      'identityEnvelope': user['identityEnvelope'],
    };
  }

  Future<Map<String, dynamic>> _login(Map<String, dynamic> data) async {
    final username = data['username'];
    final password = data['password'];
    if (username is! String || !_validUsername(username) ||
        password is! String || password.isEmpty || password.length > 256) {
      throw const ApiException('Enter your username and password.', statusCode: 400);
    }
    final user = await _findUser(username);
    if (user == null || user['passwordHash'] is! String ||
        !await _verifyPassword(password, user['passwordHash'] as String)) {
      throw const ApiException('Incorrect username or password.', statusCode: 401);
    }
    return {
      'token': _makeLocalSessionToken(user['uid'] as String, user['username'] as String),
      'user': _safeUser(user),
      'identityEnvelope': Map<String, dynamic>.from(user['identityEnvelope'] as Map),
    };
  }

  Future<Map<String, dynamic>> _createChat(Map<String, dynamic> data) async {
    final identity = _requireIdentity();
    final requestedName = data['username'];
    if (requestedName is! String || !_validUsername(requestedName.trim())) {
      throw const ApiException('Enter a valid CrazeChat username.', statusCode: 400);
    }
    final target = await _findUser(requestedName.trim());
    if (target == null) throw const ApiException('No CrazeChat user found with that username.', statusCode: 404);
    final targetId = target['uid'] as String;
    if (targetId == identity.uid) throw const ApiException('You cannot start a chat with yourself.', statusCode: 400);

    final own = await _dbGet('users/${identity.uid}');
    if (own is! Map) throw const ApiException('Your account record could not be found.', statusCode: 404);

    final orderedIds = [identity.uid, targetId]..sort();
    final digest = await Sha256().hash(utf8.encode(orderedIds.join(':')));
    final chatId = digest.bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    var chat = await _dbGet('chats/$chatId');
    if (chat == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      chat = <String, dynamic>{
        'participants': {orderedIds[0]: true, orderedIds[1]: true},
        'createdAt': now,
        'updatedAt': now,
      };
      await _dbPut('chats/$chatId', chat);
    }
    await _dbPut('userChats/${identity.uid}/$chatId', true);
    await _dbPut('userChats/$targetId/$chatId', true);
    return {'chat': await _mapChat(chatId, Map<String, dynamic>.from(chat as Map))};
  }

  Future<Map<String, dynamic>> _listChats() async {
    final identity = _requireIdentity();
    final index = await _dbGet('userChats/${identity.uid}');
    if (index == null) return {'chats': <Map<String, dynamic>>[]};
    if (index is! Map) throw const ApiException('The conversation index has an invalid format.');
    final chats = <Map<String, dynamic>>[];
    for (final chatId in index.keys) {
      if (chatId is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(chatId)) continue;
      final record = await _dbGet('chats/$chatId');
      if (record is! Map) continue;
      final mapped = await _mapChat(chatId, Map<String, dynamic>.from(record));
      chats.add({...mapped, 'lastMessageAt': record['lastMessageAt'] ?? record['updatedAt'] ?? 0});
    }
    chats.sort((a, b) => _asInt(b['lastMessageAt']).compareTo(_asInt(a['lastMessageAt'])));
    return {'chats': chats};
  }

  Future<Map<String, dynamic>> _listMessages(String chatId) async {
    final identity = _requireIdentity();
    await _requireChatMember(chatId, identity.uid);
    final records = await _dbGet('Massages/$chatId');
    if (records == null) return {'messages': <Map<String, dynamic>>[]};
    if (records is! Map) throw const ApiException('The message folder has an invalid format.');
    final messages = <Map<String, dynamic>>[];
    for (final entry in records.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      messages.add({'id': entry.key, ...Map<String, dynamic>.from(entry.value as Map)});
    }
    messages.sort((a, b) => _asInt(a['createdAt']).compareTo(_asInt(b['createdAt'])));
    return {'messages': messages};
  }

  Future<Map<String, dynamic>> _sendMessage(String chatId, Map<String, dynamic> data) async {
    final identity = _requireIdentity();
    await _requireChatMember(chatId, identity.uid);
    final ciphertext = data['ciphertext'];
    final nonce = data['nonce'];
    final mac = data['mac'];
    if (data['format'] != 'cc-e2ee-v1' || !_isBase64(ciphertext) ||
        !_isBase64(nonce, expectedBytes: 12) || !_isBase64(mac, expectedBytes: 16)) {
      throw const ApiException('Only valid encrypted message envelopes are accepted.', statusCode: 400);
    }
    if (base64Decode(ciphertext as String).length > 12000) {
      throw const ApiException('Message is too large.', statusCode: 413);
    }
    final messageId = _randomHex(16);
    final now = DateTime.now().millisecondsSinceEpoch;
    final message = <String, dynamic>{
      'id': messageId,
      'senderId': identity.uid,
      'format': 'cc-e2ee-v1',
      'ciphertext': ciphertext,
      'nonce': nonce,
      'mac': mac,
      'createdAt': now,
    };
    await _dbPut('Massages/$chatId/$messageId', message);
    await _dbPatch('chats/$chatId', {'updatedAt': now, 'lastMessageAt': now});
    return {'message': message};
  }

  Future<Map<String, dynamic>> _mapChat(String chatId, Map<String, dynamic> chat) async {
    final participants = chat['participants'];
    if (participants is! Map) throw const ApiException('A conversation has an invalid member list.');
    final members = <Map<String, dynamic>>[];
    for (final uid in participants.keys) {
      if (uid is! String || participants[uid] != true) continue;
      final record = await _dbGet('users/$uid');
      if (record is Map) members.add(_safeUser(Map<String, dynamic>.from(record)));
    }
    return {
      'id': chatId,
      'type': 'direct',
      'name': null,
      'createdAt': chat['createdAt'] ?? 0,
      'updatedAt': chat['updatedAt'] ?? 0,
      'members': members,
    };
  }

  Future<void> _requireChatMember(String chatId, String uid) async {
    final chat = await _dbGet('chats/$chatId');
    if (chat is! Map || chat['participants'] is! Map ||
        (chat['participants'] as Map)[uid] != true) {
      throw const ApiException('Conversation not found.', statusCode: 404);
    }
  }

  Future<Map<String, dynamic>?> _findUser(String username) async {
    final index = await _dbGet('usernames/${username.toLowerCase()}');
    if (index is! Map || index['uid'] is! String) return null;
    final user = await _dbGet('users/${index['uid']}');
    return user is Map ? Map<String, dynamic>.from(user) : null;
  }

  Map<String, dynamic> _safeUser(Map<String, dynamic> user) => {
    'id': user['uid'],
    'username': user['username'],
    'publicKey': user['publicKey'],
  };

  ({String uid, String username}) _requireIdentity() {
    final value = token;
    if (value == null || value.isEmpty) throw const ApiException('Sign in to continue.', statusCode: 401);
    try {
      final data = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(value))));
      if (data is Map && data['uid'] is String && data['username'] is String) {
        return (uid: data['uid'] as String, username: data['username'] as String);
      }
    } catch (_) {}
    throw const ApiException('Your local session is invalid. Please sign in again.', statusCode: 401);
  }

  String _makeLocalSessionToken(String uid, String username) =>
      base64Url.encode(utf8.encode(jsonEncode({'uid': uid, 'username': username}))).replaceAll('=', '');

  Future<String> _hashPassword(String password) async {
    final salt = _randomBytes(16);
    final key = await _passwordKdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final hash = await key.extractBytes();
    return ['pbkdf2-sha256', '310000', base64Encode(salt), base64Encode(hash)].join(r'$');
  }

  Future<bool> _verifyPassword(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256' || parts[1] != '310000') return false;
    try {
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      if (salt.length != 16 || expected.length != 32) return false;
      final key = await _passwordKdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      final actual = await key.extractBytes();
      if (actual.length != expected.length) {
        return false;
      }
      var difference = 0;
      for (var i = 0; i < actual.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _dbGet(String path) async => (await _dbCall('GET', path))['data'];
  Future<void> _dbPut(String path, Object value) async { await _dbCall('PUT', path, value); }
  Future<void> _dbPatch(String path, Map<String, dynamic> value) async { await _dbCall('PATCH', path, value); }
  Future<void> _dbDelete(String path) async { await _dbCall('DELETE', path); }

  Future<Map<String, dynamic>> _dbCall(String method, String path, [Object? body]) async {
    final configuredUrl = baseUrl.trim();
    if (configuredUrl.isEmpty || accessKey.isEmpty) {
      throw const ApiException('CrazeChat is not configured. Build with the CrazeStudio-Web BURL and KEY values.');
    }
    late final Uri uri;
    try {
      final base = Uri.parse(configuredUrl);
      if (!base.hasScheme || base.host.isEmpty || !{'https', 'http'}.contains(base.scheme)) {
        throw const FormatException('Invalid API origin');
      }
      final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
      uri = base.resolve('/db/$encodedPath');
    } on FormatException {
      throw const ApiException('CrazeStudio-Web BURL is invalid. Use the deployment origin only.');
    }

    final client = http.Client();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({'Accept': 'application/json', 'X-Access-Key': accessKey});
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await client.send(request).timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 25));
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const ApiException('CrazeStudio-Web returned an invalid JSON response.');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data['message']?.toString() ?? data['error']?.toString() ??
            'Database request failed (HTTP ${response.statusCode}).';
        throw ApiException(message, statusCode: response.statusCode);
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('CrazeStudio-Web timed out. Check the deployment and connection.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not connect to CrazeStudio-Web: ${error.message}');
    } on FormatException {
      throw const ApiException('CrazeStudio-Web returned an invalid response.');
    } catch (error) {
      throw ApiException('CrazeChat database request failed (${error.runtimeType}).');
    } finally {
      client.close();
    }
  }

  bool _validUsername(String value) => RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value);

  bool _isBase64(Object? value, {int? expectedBytes}) {
    if (value is! String || value.isEmpty ||
        !RegExp(r'^[A-Za-z0-9+/]+={0,2}
    try {
      final decoded = base64Decode(value);
      return decoded.isNotEmpty && (expectedBytes == null || decoded.length == expectedBytes);
    } catch (_) {
      return false;
    }
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _randomHex(int bytes) =>
      _randomBytes(bytes).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
}
).hasMatch(value)) {
      return false;
    }
    try {
      final decoded = base64Decode(value);
      return decoded.isNotEmpty && (expectedBytes == null || decoded.length == expectedBytes);
    } catch (_) {
      return false;
    }
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _randomHex(int bytes) =>
      _randomBytes(bytes).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
}
