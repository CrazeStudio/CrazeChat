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

/// Authenticated CrazeChat API client. No shared database credential is shipped
/// in the application; private operations use a server-issued JWT.
class CrazeChatApi {
  CrazeChatApi({this.token});

  static const apiUrl = String.fromEnvironment('BURL');
  static final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 15);

  String? token;

  Future<Map<String, dynamic>> get(String path) {
    if (path == '/chats' || path == '/auth/me') return _request('GET', path);
    final messages = RegExp(r'^/chats/([a-f0-9]{32})/messages$').firstMatch(path);
    if (messages != null) return getMessages(messages.group(1)!);
    throw const ApiException('This CrazeChat API operation is not supported.', statusCode: 404);
  }

  Future<Map<String, dynamic>> getMessages(
    String chatId, {
    int? since,
    int limit = 60,
  }) {
    _validateId(chatId, 'conversation');
    if (limit < 1 || limit > 100) {
      throw const ApiException('Message limit must be between 1 and 100.', statusCode: 400);
    }
    return _request('GET', '/chats/$chatId/messages', query: {
      'limit': '$limit',
      if (since != null && since >= 0) 'since': '$since',
    });
  }

  Future<List<Map<String, dynamic>>> getPurgedMessages(
    String chatId, {
    int? since,
  }) async {
    _validateId(chatId, 'conversation');
    final response = await _request('GET', '/chats/$chatId/purges', query: {
      if (since != null && since >= 0) 'since': '$since',
    });
    return (response['purges'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>> acknowledgeMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _request('POST', '/chats/$chatId/messages/$messageId/ack', body: const {});
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) {
    final data = body ?? const <String, dynamic>{};
    if (path == '/auth/register' || path == '/auth/login' || path == '/chats') {
      return _request('POST', path, body: data);
    }
    final messages = RegExp(r'^/chats/([a-f0-9]{32})/messages$').firstMatch(path);
    if (messages != null) return _request('POST', path, body: data);
    throw const ApiException('This CrazeChat API operation is not supported.', statusCode: 404);
  }

  Future<Map<String, dynamic>> delete(String path) {
    final match = RegExp(r'^/chats/([a-f0-9]{32})/messages/([a-f0-9]{32})$').firstMatch(path);
    if (match == null) {
      throw const ApiException('This CrazeChat delete operation is not supported.', statusCode: 404);
    }
    return _request('DELETE', path);
  }

  Future<Map<String, dynamic>> searchUsers(String query) {
    final value = query.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{2,20}$').hasMatch(value)) {
      throw const ApiException('Search with at least 2 username characters.', statusCode: 400);
    }
    return _request('GET', '/users', query: {'q': value});
  }

  String createMessageId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final configured = apiUrl.trim();
    if (configured.isEmpty) {
      throw const ApiException('CrazeChat is not configured. Set the API_URL build variable.');
    }

    late final Uri uri;
    try {
      final base = Uri.parse(configured);
      final localHost = const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host);
      if (base.host.isEmpty ||
          !{'https', if (localHost) 'http'}.contains(base.scheme) ||
          (base.path.isNotEmpty && base.path != '/') ||
          base.userInfo.isNotEmpty ||
          base.query.isNotEmpty ||
          base.fragment.isNotEmpty) {
        throw const FormatException('Invalid API origin');
      }
      uri = base.replace(path: path, queryParameters: query, fragment: null);
    } on FormatException {
      throw const ApiException('API_URL must be an HTTPS deployment origin, without a path.');
    }

    try {
      final request = http.Request(method, uri)
        ..headers['Accept'] = 'application/json';
      final currentToken = token;
      if (currentToken != null && currentToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $currentToken';
      }
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      Map<String, dynamic> data = {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data['error']?.toString() ??
            data['message']?.toString() ??
            'CrazeChat API request failed (HTTP ${response.statusCode}).';
        throw ApiException(message, statusCode: response.statusCode);
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('CrazeChat API timed out. Check your connection and deployment.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not connect to CrazeChat API: ${error.message}');
    } on FormatException {
      throw const ApiException('CrazeChat API returned an invalid response.');
    } catch (error) {
      throw ApiException('CrazeChat request failed (${error.runtimeType}).');
    }
  }

  void _validateId(String id, String label) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw ApiException('Invalid $label identifier.', statusCode: 400);
    }
  }
}
