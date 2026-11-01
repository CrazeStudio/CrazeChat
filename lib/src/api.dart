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

/// CrazeChat REST client. All database access goes through CrazeStudio-Web;
/// the app sends the shared build-time KEY in X-Access-Key and the user's
/// short-lived JWT separately in Authorization.
class CrazeChatApi {
  CrazeChatApi({this.token});

  static const apiUrl = String.fromEnvironment('BURL');
  static const apiKey = String.fromEnvironment('KEY');
  static final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 20);
  static const _idPattern = r'^[a-f0-9]{32}$';
  String? token;

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required Map<String, dynamic> identityEnvelope,
  }) => _request('POST', 'auth/register', body: {
    'username': username,
    'password': password,
    'identityEnvelope': identityEnvelope,
  });

  Future<Map<String, dynamic>> login({required String username, required String password}) =>
      _request('POST', 'auth/login', body: {'username': username, 'password': password});

  Future<Map<String, dynamic>> restoreSession() => _request('GET', 'auth/session');
  Future<Map<String, dynamic>> listChats() => _request('GET', 'chats');
  Future<Map<String, dynamic>> createChat(String username) =>
      _request('POST', 'chats', body: {'username': username});

  Future<Map<String, dynamic>> searchUsers(String query) {
    final value = query.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{2,20}$').hasMatch(value)) {
      throw const ApiException('Search with at least 2 username characters.', statusCode: 400);
    }
    return _request('GET', 'users/search', query: {'query': value});
  }

  Future<Map<String, dynamic>> getMessages(String chatId, {int? since, int limit = 60}) {
    _validateId(chatId, 'conversation');
    if (limit < 1 || limit > 100) {
      throw const ApiException('Message limit must be between 1 and 100.', statusCode: 400);
    }
    return _request('GET', 'chats/$chatId/messages', query: {
      if (since != null && since >= 0) 'since': '$since',
      'limit': '$limit',
    });
  }

  Future<List<Map<String, dynamic>>> getPurgedMessages(String chatId, {int? since}) async {
    _validateId(chatId, 'conversation');
    final result = await _request('GET', 'chats/$chatId/purges', query: {
      if (since != null && since >= 0) 'since': '$since',
    });
    return (result['purges'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage(String chatId, Map<String, dynamic> message) {
    _validateId(chatId, 'conversation');
    _validateId(message['id']?.toString() ?? '', 'message');
    return _request('POST', 'chats/$chatId/messages', body: {
      'message': Map<String, dynamic>.from(message),
    });
  }

  Future<Map<String, dynamic>> deleteMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _request('DELETE', 'chats/$chatId/messages/$messageId');
  }

  Future<Map<String, dynamic>> acknowledgeMessage(String chatId, String messageId) {
    _validateId(chatId, 'conversation');
    _validateId(messageId, 'message');
    return _request('POST', 'chats/$chatId/purges/$messageId/acknowledge');
  }

  String createMessageId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
  }) async {
    final configured = apiUrl.trim();
    if (configured.isEmpty) {
      throw const ApiException('CrazeChat is not configured. Set the BURL build variable to your CrazeStudio-Web origin.');
    }
    final sharedKey = apiKey.trim();
    if (sharedKey.isEmpty) {
      throw const ApiException('CrazeChat is not configured. Set the KEY build variable to the same value as the backend ACCESS_KEY.');
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
      uri = base.replace(
        path: '/db/$path',
        queryParameters: query.isEmpty ? null : query,
      );
    } on FormatException {
      throw const ApiException('BURL must be an HTTPS CrazeStudio-Web origin, without a path.');
    }

    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'X-Access-Key': sharedKey,
      };
      if (body != null) headers['Content-Type'] = 'application/json';
      final currentToken = token;
      if (currentToken != null && currentToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $currentToken';
      }
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      Map<String, dynamic> result = {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) result = decoded;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          result['message']?.toString() ?? result['error']?.toString() ??
              'CrazeChat request failed (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
          code: result['error']?.toString(),
        );
      }
      if (result['ok'] == false) {
        throw ApiException(
          result['message']?.toString() ?? 'CrazeChat request failed.',
          code: result['error']?.toString(),
        );
      }
      final payload = result['result'];
      return payload is Map ? Map<String, dynamic>.from(payload) : result;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('CrazeChat request timed out. Check your connection and try again.');
    } on http.ClientException catch (error) {
      throw ApiException('Could not connect to CrazeStudio-Web: ${error.message}');
    } on FormatException {
      throw const ApiException('CrazeStudio-Web returned an invalid JSON response.');
    } catch (error) {
      throw ApiException('CrazeChat request failed (${error.runtimeType}).');
    }
  }

  void _validateId(String id, String label) {
    if (!RegExp(_idPattern).hasMatch(id)) {
      throw ApiException('Invalid $label identifier.', statusCode: 400);
    }
  }
}
