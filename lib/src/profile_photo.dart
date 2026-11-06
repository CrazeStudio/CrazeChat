import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Downloads profile images once and keeps a bounded encrypted local copy.
/// The backend stores only the URL; image bytes remain on the user's device.
class ProfilePhotoCache {
  static const _storage = FlutterSecureStorage();
  static const _maxBytes = 256 * 1024;

  static bool isValidUrl(String value) {
    if (value.length > 2048) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.hasFragment == false;
  }

  static Future<Uint8List?> load({
    required String userId,
    required String url,
  }) async {
    if (userId.isEmpty || !isValidUrl(url)) return null;
    final urlKey = 'profilePhotoCacheUrl_$userId';
    final bytesKey = 'profilePhotoBytes_$userId';
    try {
      final cachedUrl = await _storage.read(key: urlKey);
      final cachedBytes = await _storage.read(key: bytesKey);
      if (cachedUrl == url && cachedBytes != null) {
        final decoded = UriData.parse('data:application/octet-stream;base64,$cachedBytes').contentAsBytes();
        if (decoded.isNotEmpty && decoded.length <= _maxBytes) return decoded;
      }

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url))
          ..followRedirects = true
          ..maxRedirects = 3
          ..headers['Accept'] = 'image/jpeg,image/png,image/webp,image/gif';
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        final finalUrl = response.request?.url;
        final contentType = (response.headers['content-type'] ?? '')
            .split(';')
            .first
            .trim()
            .toLowerCase();
        if (response.statusCode != 200 ||
            finalUrl == null ||
            finalUrl.scheme != 'https' ||
            !{'image/jpeg', 'image/png', 'image/webp', 'image/gif'}.contains(contentType)) {
          return null;
        }

        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (builder.length + chunk.length > _maxBytes) return null;
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        if (bytes.isEmpty) return null;
        final encoded = UriData.fromBytes(bytes).toString().split(',').last;
        await _storage.write(key: bytesKey, value: encoded);
        await _storage.write(key: urlKey, value: url);
        return bytes;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String userId) async {
    await _storage.delete(key: 'profilePhotoCacheUrl_$userId');
    await _storage.delete(key: 'profilePhotoBytes_$userId');
  }
}
