import 'dart:convert';
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

  // Injected by GitHub Actions from repository secrets BURL and KEY.
  static const baseUrl = String.fromEnvironment('BURL');
  static const accessKey = String.fromEnvironment('KEY');

  String? token;

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final configuredUrl = baseUrl.trim();
    if (configuredUrl.isEmpty || accessKey.isEmpty) {
      throw const ApiException(
        'CrazeChat is not configured. Build the app with the BURL and KEY settings.',
      );
    }

    late final Uri uri;
    try {
      uri = Uri.parse(configuredUrl).resolve(path);
      if (!uri.hasScheme || uri.host.isEmpty || !{'https', 'http'}.contains(uri.scheme)) {
        throw const FormatException('Invalid API URL');
      }
    } on FormatException {
      throw const ApiException('CrazeChat API URL (BURL) is invalid.');
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'X-API-Key': accessKey,
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final client = http.Client();
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await client.send(request).timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed);
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          data['error']?.toString() ?? 'Request failed (' + response.statusCode.toString() + ').',
          statusCode: response.statusCode,
        );
      }
      return data;
    } catch (error) {
      if (error is ApiException) rethrow;
      throw const ApiException('Cannot reach CrazeChat. Check your internet connection and API deployment.');
    } finally {
      client.close();
    }
  }
}
