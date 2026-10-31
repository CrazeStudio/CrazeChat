import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

/// HTTP client for the CrazeChat API.
///
/// Firebase paths are deliberately owned by the backend. The app talks to
/// authenticated REST resources and never constructs Firebase paths itself.
class CrazeChatApi {
  CrazeChatApi({this.token});

  static const apiUrl = String.fromEnvironment('BURL');
  static const gatewayKey = String.fromEnvironment('KEY');
  static final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 20);
  static const _idPattern = r'^[a-f0-9]{32}$';

  String? token;

  Uri get _baseUri {
    final configured = apiUrl.trim();
    if (configured.isEmpty) {
      throw const ApiException('CrazeChat is not configured. Set the BURL build variable.');
    }
    try {
      final base = Uri.parse(configured);
      final localHost = const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host);
      if (base.host.isEmpty ||
          !{'https', if (localHost) 'http'}.contains(base.scheme) ||
          base.userInfo.isNotEmpty ||
          base.query.isNotEmpty ||
          base.fragment.isNotEmpty) {
        throw const FormatException('Invalid API origin');
      }
      return base;
    } on FormatException {
      throw const ApiException('BURL must be a valid HTTPS API origin.');
    }
  }

  Uri _uri(String path, [Map<String, Object?> query = const {}]) {
    final base = _baseUri;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = base.resolve(normalizedPath);
    final parameters = <String, String>{
      for (final entry in query.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
    return uri.replace(queryParameters: parameters.isEmpty ? null : parameters);
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    // KEY is the shared API access credential; the user's JWT remains separate.
    if (gatewayKey.isNotEmpty) headers['X-Access-Key'] = gatewayKey;
    final currentToken = token;
    if (currentToken != null && currentToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $currentToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, dynamic>? body,
  }) async {
    late final http.Response response;
    try {
      final uri = _uri(path, query);
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('CrazeChat request timed out. Check your connection.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not connect to CrazeChat: ${error.message}');
    } on FormatException {
      throw const ApiException('CrazeChat returned an invalid response.');
    } catch (error) {
      throw ApiException('CrazeChat request failed (${error.runtimeType}).');
    }

    Map<String, dynamic> result = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) result = Map<String, dynamic>.from(decoded);
      } on FormatException {
        throw const ApiException('CrazeChat returned invalid JSON.');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        result['error']?.toString() ??
            result['message']?.toString() ??
            'CrazeChat request failed (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        code: result['code']?.toString() ?? result['errorCode']?.toString(),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required Map<String, dynamic> identityEnvelope,
  }) async {
    final result = await _request('POST', '/auth/register', body: {
      'username': username,
      'password': password,
      'publicKey': identityEnvelope['publicKey'],
      'identityEnvelope': identityEnvelope,
    });
    return result;
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) => _request('POST', '/auth/login', body: {
    'username': username,
    'password': password,
  });

  Future<Map<String, dynamic>> restoreSession() => _request('GET', '/auth/me');

  Future<Map<String, dynamic>> listChats() => _request('GET', '/chats');

  Future<Map<String, dynamic>> createChat(String username) =>
      _request('POST', '/chats', body: {'username': username});

  Future<Map<String, dynamic>> searchUsers(String query) {
    final value = query.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{2,20}$').hasMatch(value)) {
      throw const ApiException('Search with at least 2 username characters.', statusCode: 400);
    }
    return _request('GET', '/users', query: {'q': value});
  }

  Future<Map<String, dynamic>> getMessages(
    String chatId, {
    int? since,
    int limit = 60,
  }) async {
    _validateId(chatId, 'conversation');
    if (limit < 1 || limit > 100) {
      throw const ApiException('Message limit must be between 1 and 100.', statusCode: 400);
    }
    final result = await _request('GET', '/chats/$chatId/messages', query: {
      'since': since != null && since >= 0 ? since : null,
      'limit': limit,
    });
    final messages = (result['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => _normalizeMessage(Map<String, dynamic>.from(entry)))
        .toList();
    return {...result, 'messages': messages};
  }

  Future<List<Map<String, dynamic>>> getPurgedMessages(
    String chatId, {
    int? since,
  }) async {
    _validateId(chatId, 'conversation');
    final result = await _request('GET', '/chats/$chatId/purges', query: {
      'since': since != null && since >= 0 ? since : null,
    });
    return (result['purges'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage(
    String chatId,
    Map<String, dynamic> message,
  ) async {
    _validateId(chatId, 'conversation');
    _validateId(message['id']?.toString() ?? '', 'message');
    final result = await _request('POST', '/chats/$chatId/messages', body: {
      'id': message['id'],
      'format': message['format'] ?? 'cc-e2ee-v1',
      'ciphertext': message['ciphertext'],
      'nonce': message['nonce'],
      'mac': message['mac'],
    });
    if (result['message'] is Map) {
      result['message'] = _normalizeMessage(
        Map<String, dynamic>.from(result['message'] as Map),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> deleteMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _request('DELETE', '/chats/$chatId/messages/$messageId');
  }

  Future<Map<String, dynamic>> acknowledgeMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _request('POST', '/chats/$chatId/messages/$messageId/ack', body: const {});
  }

  String createMessageId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Supports the new Firebase record shape and the previous API envelope.
  /// The UI and crypto layer receive one stable, flat message representation.
  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> source) {
    final information = source['Information'];
    final info = information is Map
        ? Map<String, dynamic>.from(information)
        : <String, dynamic>{};
    final messageText = info['massage'] ?? info['message'];
    return {
      ...source,
      'id': source['id'] ?? source['messageId'],
      'senderId': source['senderId'] ?? info['Sender user id'] ?? info['senderId'],
      'createdAt': source['createdAt'] ?? info['Timestamp'] ?? info['timestamp'],
      if (source['format'] == null) 'format': 'cc-e2ee-v1',
      if (source['ciphertext'] == null && messageText is String)
        'ciphertext': messageText,
      if (source['nonce'] == null && info['nonce'] != null) 'nonce': info['nonce'],
      if (source['mac'] == null && info['mac'] != null) 'mac': info['mac'],
    };
  }

  void _validateId(String id, String label) {
    if (!RegExp(_idPattern).hasMatch(id)) {
      throw ApiException('Invalid $label identifier.', statusCode: 400);
    }
  }

  static void close() => _client.close();
}
