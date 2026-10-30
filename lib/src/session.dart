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
      if (saved != null) savedAccounts = (jsonDecode(saved) as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
      token = await _storage.read(key: 'token');
      username = await _storage.read(key: 'username');
      userId = await _storage.read(key: 'userId');
      final encoded = await _storage.read(key: 'identityEnvelope');
      if (encoded != null) identityEnvelope = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      if (token == null || username == null || userId == null || identityEnvelope == null) {
        await _storage.deleteAll();
        token = null; username = null; userId = null; identityEnvelope = null;
      } else {
        api.token = token;
      }
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
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'userId', value: userId);
    await _storage.write(key: 'identityEnvelope', value: jsonEncode(identityEnvelope));
    savedAccounts.removeWhere((item) => item['userId'] == userId);
    savedAccounts.insert(0, {'token': token, 'username': username, 'userId': userId, 'identityEnvelope': identityEnvelope});
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
    for (final item in savedAccounts) { if (item['userId'] == targetId) { account = item; break; } }
    if (account == null) return;
    identity = null; token = account['token'] as String; username = account['username'] as String;
    userId = account['userId'] as String; identityEnvelope = Map<String, dynamic>.from(account['identityEnvelope'] as Map);
    api.token = token; await _persistActive(); notifyListeners();
  }

  Future<void> addAccount() async {
    identity = null; token = null; username = null; userId = null; identityEnvelope = null; api.token = null;
    await _storage.delete(key: 'token'); await _storage.delete(key: 'username');
    await _storage.delete(key: 'userId'); await _storage.delete(key: 'identityEnvelope'); notifyListeners();
  }

  Future<void> signOut() async {
    savedAccounts.removeWhere((item) => item['userId'] == userId);
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    identity = null; token = null; username = null; userId = null; identityEnvelope = null; api.token = null;
    await _storage.delete(key: 'token'); await _storage.delete(key: 'username');
    await _storage.delete(key: 'userId'); await _storage.delete(key: 'identityEnvelope'); notifyListeners();
  }

  Future<void> _persistActive() async {
    await _storage.write(key: 'token', value: token); await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'userId', value: userId); await _storage.write(key: 'identityEnvelope', value: jsonEncode(identityEnvelope));
  }

  void lock() { identity = null; notifyListeners(); }
}