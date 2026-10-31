import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// All app features use one /db operation endpoint. The backend dispatcher is
/// deliberately implemented as a separate deployment phase.
class CrazeChatApi {
  CrazeChatApi({this.token});

  static const apiUrl = String.fromEnvironment('BURL');
  static final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 15);
  static const _idPattern = r'^[a-f0-9]{32}$';
  String? token;

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required Map<String, dynamic> identityEnvelope,
  }) => _db('auth.register', {
    'username': username,
    'password': password,
    'publicKey': identityEnvelope['publicKey'],
    'identityEnvelope': identityEnvelope,
  });

  Future<Map<String, dynamic>> login({required String username, required String password}) =>
      _db('auth.login', {'username': username, 'password': password});

  Future<Map<String, dynamic>> restoreSession() => _db('auth.session', const {});
  Future<Map<String, dynamic>> listChats() => _db('chats.list', const {});
  Future<Map<String, dynamic>> createChat(String username) => _db('chats.create', {'username': username});

  Future<Map<String, dynamic>> searchUsers(String query) {
    final value = query.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{2,20}$').hasMatch(value)) {
      throw const ApiException('Search with at least 2 username characters.', statusCode: 400);
    }
    return _db('users.search', {'query': value});
  }

  Future<Map<String, dynamic>> getMessages(String chatId, {int? since, int limit = 60}) {
    _validateId(chatId, 'conversation');
    if (limit < 1 || limit > 100) {
      throw const ApiException('Message limit must be between 1 and 100.', statusCode: 400);
    }
    return _db('messages.list', {
      'chatId': chatId,
      if (since != null && since >= 0) 'since': since,
      'limit': limit,
    });
  }

  Future<List<Map<String, dynamic>>> getPurgedMessages(String chatId, {int? since}) async {
    _validateId(chatId, 'conversation');
    final result = await _db('cloudpurge.list', {
      'chatId': chatId,
      if (since != null && since >= 0) 'since': since,
    });
    return (result['purges'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage(String chatId, Map<String, dynamic> message) {
    _validateId(chatId, 'conversation');
    _validateId(message['id']?.toString() ?? '', 'message');
    return _db('messages.send', {
      'chatId': chatId,
      'message': Map<String, dynamic>.from(message),
    });
  }

  Future<Map<String, dynamic>> deleteMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _db('messages.delete', {'chatId': chatId, 'messageId': messageId});
  }

  Future<Map<String, dynamic>> acknowledgeMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _db('cloudpurge.acknowledge', {'chatId': chatId, 'messageId': messageId});
  }

  String createMessageId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, dynamic>> _db(String operation, Map<String, dynamic> data) async {
    final configured = apiUrl.trim();
    if (configured.isEmpty) {
      throw const ApiException('CrazeChat is not configured. Set the BURL build variable.');
    }
    late final Uri uri;
    try {
      final base = Uri.parse(configured);
      final localHost = const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host);
      if (base.host.isEmpty || !{'https', if (localHost) 'http'}.contains(base.scheme) ||
          (base.path.isNotEmpty && base.path != '/') || base.userInfo.isNotEmpty ||
          base.query.isNotEmpty || base.fragment.isNotEmpty) {
        throw const FormatException('Invalid API origin');
      }
      uri = base.replace(path: '/db');
    } on FormatException {
      throw const ApiException('BURL must be an HTTPS deployment origin, without a path.');
    }

    try {
      final request = http.Request('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'operation': operation, 'data': data});
      final currentToken = token;
      if (currentToken != null && currentToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $currentToken';
      }
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      Map<String, dynamic> result = {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) result = decoded;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(result['message']?.toString() ?? result['error']?.toString() ??
            'CrazeChat /db request failed (HTTP ${response.statusCode}).',
            statusCode: response.statusCode);
      }
      if (result['ok'] == false) {
        throw ApiException(result['message']?.toString() ?? 'CrazeChat operation failed.');
      }
      final payload = result['result'];
      return payload is Map ? Map<String, dynamic>.from(payload) : result;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('CrazeChat /db request timed out. Check your connection and deployment.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not connect to CrazeChat /db: ${error.message}');
    } on FormatException {
      throw const ApiException('CrazeChat /db returned an invalid JSON response.');
    } catch (error) {
      throw ApiException('CrazeChat /db request failed (${error.runtimeType}).');
    }
  }

  void _validateId(String id, String label) {
    if (!RegExp(_idPattern).hasMatch(id)) {
      throw ApiException('Invalid $label identifier.', statusCode: 400);
    }
  }
}
