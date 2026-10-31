import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'crypto_service.dart';

class ChatSession extends ChangeNotifier {
  ChatSession() : api = CrazeChatApi();
  static const _storage = FlutterSecureStorage();
  final CrazeChatApi api;

  bool ready = false;
  String? token, username, userId;
  Map<String, dynamic>? identityEnvelope;
  KeyPair? identity;
  List<Map<String, dynamic>> savedAccounts = [];
  static const _accountsKey = 'savedAccounts';

  bool get signedIn => token != null && username != null;
  bool get unlocked => identity != null;

  Future<void> restore() async {
    try {
      final saved = await _storage.read(key: _accountsKey);
      if (saved != null) {
        savedAccounts = (jsonDecode(saved) as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
      }
      token = await _storage.read(key: 'token');
      username = await _storage.read(key: 'username');
      userId = await _storage.read(key: 'userId');
      final encoded = await _storage.read(key: 'identityEnvelope');
      if (encoded != null) {
        identityEnvelope = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      }
      if (token == null || username == null || userId == null || identityEnvelope == null) {
        await _clearActiveSession();
      } else {
        api.token = token;
        try {
          // Previous builds stored unsigned local claims. The new API rejects
          // them, so users must sign in again instead of trusting local tokens.
          await api.get('/auth/me');
        } on ApiException catch (error) {
          if (error.statusCode == 401 || error.statusCode == 403) {
            savedAccounts.removeWhere((account) => account['userId'] == userId);
            await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
            await _clearActiveSession();
          }
        }
        if (token != null && !savedAccounts.any((item) => item['userId'] == userId)) {
          savedAccounts.insert(0, {
            'token': token,
            'username': username,
            'userId': userId,
            'identityEnvelope': identityEnvelope,
          });
          if (savedAccounts.length > 2) savedAccounts = savedAccounts.take(2).toList();
          await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
        }
      }
    } catch (_) {
      // Keep the app recoverable if secure storage or the network is unavailable.
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> acceptSession(Map<String, dynamic> response, KeyPair keyPair) async {
    final user = Map<String, dynamic>.from(response['user'] as Map);
    token = response['token'] as String;
    username = user['username'] as String;
    userId = user['id'] as String;
    identityEnvelope = Map<String, dynamic>.from(response['identityEnvelope'] as Map);
    identity = keyPair;
    api.token = token;
    await _persistActive();
    savedAccounts.removeWhere((item) => item['userId'] == userId);
    savedAccounts.insert(0, {
      'token': token,
      'username': username,
      'userId': userId,
      'identityEnvelope': identityEnvelope,
    });
    if (savedAccounts.length > 2) savedAccounts = savedAccounts.take(2).toList();
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    notifyListeners();
  }

  Future<void> unlock(String password) async {
    final envelope = identityEnvelope;
    if (envelope == null) throw const FormatException('No encrypted identity was saved.');
    identity = await CryptoService.unlockIdentity(envelope, password);
    notifyListeners();
  }

  Future<void> switchAccount(String targetId) async {
    Map<String, dynamic>? account;
    for (final item in savedAccounts) {
      if (item['userId'] == targetId) {
        account = item;
        break;
      }
    }
    if (account == null) return;
    identity = null;
    token = account['token'] as String;
    username = account['username'] as String;
    userId = account['userId'] as String;
    identityEnvelope = Map<String, dynamic>.from(account['identityEnvelope'] as Map);
    api.token = token;
    await _persistActive();
    notifyListeners();
  }

  Future<void> addAccount() async {
    identity = null;
    token = null;
    username = null;
    userId = null;
    identityEnvelope = null;
    api.token = null;
    await _clearActiveSession();
    notifyListeners();
  }

  Future<void> signOut() async {
    savedAccounts.removeWhere((account) => account['userId'] == userId);
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    identity = null;
    token = null;
    username = null;
    userId = null;
    identityEnvelope = null;
    api.token = null;
    await _clearActiveSession();
    notifyListeners();
  }

  Future<void> _clearActiveSession() async {
    token = null;
    username = null;
    userId = null;
    identityEnvelope = null;
    identity = null;
    api.token = null;
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'userId');
    await _storage.delete(key: 'identityEnvelope');
  }

  Future<void> _persistActive() async {
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'userId', value: userId);
    await _storage.write(key: 'identityEnvelope', value: jsonEncode(identityEnvelope));
  }

  String _messageIndexKey(String chatId) => 'cc_msg_index_${userId}_$chatId';
  String _messageKey(String chatId, String messageId) => 'cc_msg_${userId}_${chatId}_$messageId';

  /// Persists only the encrypted envelope and delivery metadata. The receipt
  /// endpoint must not be called until this Future completes successfully.
  Future<void> saveCachedMessage(String chatId, Map<String, dynamic> message) async {
    final uid = userId;
    final id = message['id'];
    if (uid == null || id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(chatId) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid local message cache record.');
    }
    const allowed = ['id', 'senderId', 'format', 'ciphertext', 'nonce', 'mac', 'createdAt', 'deliveryState'];
    final safe = <String, dynamic>{
      for (final field in allowed)
        if (message.containsKey(field)) field: message[field],
    };
    await _storage.write(key: _messageKey(chatId, id), value: jsonEncode(safe));

    final indexKey = _messageIndexKey(chatId);
    final encodedIndex = await _storage.read(key: indexKey);
    List<String> ids = [];
    if (encodedIndex != null) {
      try {
        ids = (jsonDecode(encodedIndex) as List).whereType<String>().toList();
      } catch (_) {
        ids = [];
      }
    }
    if (!ids.contains(id)) {
      ids.add(id);
      await _storage.write(key: indexKey, value: jsonEncode(ids));
    }
  }

  Future<List<Map<String, dynamic>>> loadCachedMessages(String chatId) async {
    if (userId == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(chatId)) return [];
    final encodedIndex = await _storage.read(key: _messageIndexKey(chatId));
    if (encodedIndex == null) return [];
    final ids = (jsonDecode(encodedIndex) as List).whereType<String>();
    final records = <Map<String, dynamic>>[];
    for (final id in ids) {
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) continue;
      final encoded = await _storage.read(key: _messageKey(chatId, id));
      if (encoded == null) continue;
      try {
        records.add(Map<String, dynamic>.from(jsonDecode(encoded) as Map));
      } catch (_) {
        // Ignore corrupt cache entries; the next sync can recover the message.
      }
    }
    records.sort((a, b) => _asInt(a['createdAt']).compareTo(_asInt(b['createdAt'])));
    return records;
  }

  Future<void> updateCachedMessage(
    String chatId,
    String messageId, {
    required String deliveryState,
    Map<String, dynamic>? serverMessage,
  }) async {
    final existing = await _storage.read(key: _messageKey(chatId, messageId));
    if (existing == null) return;
    final message = Map<String, dynamic>.from(jsonDecode(existing) as Map);
    if (serverMessage != null) {
      for (final field in ['senderId', 'format', 'ciphertext', 'nonce', 'mac', 'createdAt']) {
        if (serverMessage.containsKey(field)) message[field] = serverMessage[field];
      }
    }
    message['deliveryState'] = deliveryState;
    await saveCachedMessage(chatId, message);
  }

  Future<void> deleteCachedMessage(String chatId, String messageId) async {
    if (userId == null) return;
    await _storage.delete(key: _messageKey(chatId, messageId));
    final indexKey = _messageIndexKey(chatId);
    final encoded = await _storage.read(key: indexKey);
    if (encoded == null) return;
    final ids = (jsonDecode(encoded) as List).whereType<String>()
        .where((id) => id != messageId).toList();
    await _storage.write(key: indexKey, value: jsonEncode(ids));
  }

  Future<int> getCachedMessageCount() async {
    final uid = userId;
    if (uid == null) return 0;
    final all = await _storage.readAll();
    return all.keys.where((key) => key.startsWith('cc_msg_${uid}_') && !key.contains('index')).length;
  }

  int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  void lock() {
    identity = null;
    notifyListeners();
  }
}
