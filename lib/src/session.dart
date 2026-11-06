import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'push_notifications.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'crypto_service.dart';

class ChatSession extends ChangeNotifier {
  ChatSession() : api = CrazeChatApi();
  static const _storage = FlutterSecureStorage();
  static const _manualLockKey = 'pref_manual_lock';
  final CrazeChatApi api;

  bool ready = false;
  bool notificationsEnabled = true;
  bool soundEffectsEnabled = true;
  bool vibrationEnabled = true;
  ThemeMode themeMode = ThemeMode.system;
  String? token, username, userId, photoUrl;
  Map<String, dynamic>? identityEnvelope;
  KeyPair? identity;
  List<Map<String, dynamic>> savedAccounts = [];
  static const _accountsKey = 'savedAccounts';
  static const _trustedContactKeysKey = 'trustedContactPublicKeyFingerprints';
  static final _chatIdPattern = RegExp(r'^[a-f0-9]{32}$');
  static final _messageIdPattern = RegExp(r'^[a-f0-9]{32}$');
  final Map<String, Future<void>> _cacheWriteQueues = {};

  bool get signedIn => token != null && username != null;
  bool get unlocked => identity != null;

  Future<void> restore() async {
    try {
      notificationsEnabled =
          (await _storage.read(key: 'pref_notifications')) != 'false';
      soundEffectsEnabled =
          (await _storage.read(key: 'pref_sound_effects')) != 'false';
      vibrationEnabled =
          (await _storage.read(key: 'pref_vibration')) != 'false';
      await _storage.delete(key: 'pref_auto_lock_backgrounded_at');
      await _storage.delete(key: 'pref_auto_lock');
      final manuallyLocked = await _storage.read(key: _manualLockKey) == 'true';
      final requireIdentityUnlock = manuallyLocked;
      themeMode = switch (await _storage.read(key: 'pref_theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      final saved = await _storage.read(key: _accountsKey);
      if (saved != null) {
        savedAccounts = (jsonDecode(saved) as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
      }
      token = await _storage.read(key: 'token');
      username = await _storage.read(key: 'username');
      userId = await _storage.read(key: 'userId');
      photoUrl = userId == null ? null : await _storage.read(key: 'profilePhotoUrl_$userId');
      final encoded = await _storage.read(key: 'identityEnvelope');
      if (encoded != null) {
        identityEnvelope = Map<String, dynamic>.from(
          jsonDecode(encoded) as Map,
        );
      }
      if (token == null ||
          username == null ||
          userId == null ||
          identityEnvelope == null) {
        await _clearActiveSession();
      } else {
        api.token = token;
        try {
          // Previous builds stored unsigned local claims. The new API rejects
          // them, so users must sign in again instead of trusting local tokens.
          final restored = await api.restoreSession();
          final restoredUser = Map<String, dynamic>.from(restored['user'] as Map);
          photoUrl = restoredUser['photoUrl'] as String?;
          await _storage.write(key: 'profilePhotoUrl_$userId', value: photoUrl);
          for (final account in savedAccounts) {
            if (account['userId'] == userId) account['photoUrl'] = photoUrl;
          }
          await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
        } on ApiException catch (error) {
          // The generic CrazeStudio-Web gateway also returns 401 for a missing
          // or mismatched shared gateway credential. That is not proof that the
          // user's saved JWT is invalid; never erase local accounts on that response.
          if ((error.statusCode == 401 || error.statusCode == 403) &&
              error.code != 'UNAUTHORIZED' &&
              error.code != 'GATEWAY_NOT_CONFIGURED') {
            savedAccounts.removeWhere((account) => account['userId'] == userId);
            await _storage.write(
              key: _accountsKey,
              value: jsonEncode(savedAccounts),
            );
            await _clearActiveSession();
          }
        }
        if (token != null && userId != null && identityEnvelope != null) {
          final savedPrivateKey = await _storage.read(
            key: 'identityPrivateKey_$userId',
          );
          if (savedPrivateKey != null && !requireIdentityUnlock) {
            try {
              identity = await CryptoService.restoreIdentityFromPrivateBytes(
                identityEnvelope!,
                base64Decode(savedPrivateKey),
              );
            } catch (_) {
              await _storage.delete(key: 'identityPrivateKey_$userId');
            }
          }
        }
        if (token != null &&
            !savedAccounts.any((item) => item['userId'] == userId)) {
          savedAccounts.insert(0, {
            'token': token,
            'username': username,
            'userId': userId,
            'identityEnvelope': identityEnvelope,
            'photoUrl': photoUrl,
          });
          if (savedAccounts.length > 2) {
            savedAccounts = savedAccounts.take(2).toList();
          }
          await _storage.write(
            key: _accountsKey,
            value: jsonEncode(savedAccounts),
          );
        }
      }
    } catch (_) {
      // Keep the app recoverable if secure storage or the network is unavailable.
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> acceptSession(
    Map<String, dynamic> response,
    IdentityMaterial material,
  ) async {
    final user = Map<String, dynamic>.from(response['user'] as Map);
    token = response['token'] as String;
    username = user['username'] as String;
    userId = user['id'] as String;
    photoUrl = user['photoUrl'] as String?;
    final serverEnvelope = Map<String, dynamic>.from(response['identityEnvelope'] as Map);
    identityEnvelope = Map<String, dynamic>.from(material.envelope);
    _destroyIdentity();
    identity = material.keyPair;
    api.token = token;
    if (serverEnvelope['version'] != material.envelope['version'] || serverEnvelope['keyProtection'] != material.envelope['keyProtection']) {
      await api.updateIdentityEnvelope(material.envelope);
    }
    await _storage.delete(key: _manualLockKey);
    await _storage.write(
      key: 'identityPrivateKey_$userId',
      value: base64Encode(material.privateKeyBytes),
    );
    await _persistActive();
    savedAccounts.removeWhere((item) => item['userId'] == userId);
    savedAccounts.insert(0, {
      'token': token,
      'username': username,
      'userId': userId,
      'identityEnvelope': identityEnvelope,
      'photoUrl': photoUrl,
    });
    if (savedAccounts.length > 2) {
      savedAccounts = savedAccounts.take(2).toList();
    }
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    notifyListeners();
  }

  Future<String> contactKeyStatus({
    required String contactId,
    required String publicKey,
  }) async {
    final fingerprint = await CryptoService.fingerprintPublicKey(publicKey);
    final encoded = await _storage.read(key: _trustedContactKeysKey);
    if (encoded == null) return 'unverified';
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return 'unverified';
      final previous = decoded[contactId];
      if (previous == null) return 'unverified';
      return previous == fingerprint ? 'verified' : 'changed';
    } catch (_) {
      return 'unverified';
    }
  }

  Future<void> trustContactKey({
    required String contactId,
    required String publicKey,
  }) async {
    final fingerprint = await CryptoService.fingerprintPublicKey(publicKey);
    final encoded = await _storage.read(key: _trustedContactKeysKey);
    Map<String, dynamic> trusted = {};
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) trusted = Map<String, dynamic>.from(decoded);
      } catch (_) {
        trusted = {};
      }
    }
    trusted[contactId] = fingerprint;
    await _storage.write(key: _trustedContactKeysKey, value: jsonEncode(trusted));
  }

  Future<void> updateProfilePhoto(String? nextPhotoUrl) async {
    if (!signedIn || userId == null) {
      throw const FormatException('Sign in before changing your profile photo.');
    }
    final normalized = nextPhotoUrl?.trim();
    final value = normalized == null || normalized.isEmpty ? null : normalized;
    final result = await api.updateProfilePhoto(value);
    final user = Map<String, dynamic>.from(result['user'] as Map);
    photoUrl = user['photoUrl'] as String?;
    for (final account in savedAccounts) {
      if (account['userId'] == userId) account['photoUrl'] = photoUrl;
    }
    await _storage.write(key: 'profilePhotoUrl_$userId', value: photoUrl);
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    notifyListeners();
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final currentIdentity = identity;
    final uid = userId;
    if (!signedIn || identityEnvelope == null || currentIdentity == null || uid == null) {
      throw const FormatException('Unlock your CrazeChat identity before changing your password.');
    }
    final material = await CryptoService.rewrapUnlockedIdentity(identity: currentIdentity, password: newPassword);
    await api.changePassword(currentPassword: currentPassword, newPassword: newPassword, identityEnvelope: material.envelope);
    identityEnvelope = material.envelope;
    await _storage.write(key: 'identityPrivateKey_$uid', value: base64Encode(material.privateKeyBytes));
    await _persistActive();
    for (final account in savedAccounts) { if (account['userId'] == uid) account['identityEnvelope'] = material.envelope; }
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    notifyListeners();
  }

  Future<IdentityMaterial> unlockForLogin({required Map<String, dynamic> envelope, required String password, required String accountId}) async {
    if (envelope['version'] == 2) {
      final saved = await _storage.read(key: 'identityPrivateKey_$accountId');
      if (saved == null) throw const FormatException('This account uses an older separate encryption passphrase. Open it on a device where it is already unlocked to migrate automatically.');
      final keyPair = await CryptoService.restoreIdentityFromPrivateBytes(envelope, base64Decode(saved));
      return CryptoService.rewrapUnlockedIdentity(identity: keyPair, password: password);
    }
    final material = await CryptoService.unlockIdentityMaterial(envelope, password);
    if (envelope['version'] != 3 || envelope['keyProtection'] != 'account-password-v3') {
      return CryptoService.rewrapUnlockedIdentity(identity: material.keyPair, password: password);
    }
    return material;
  }

  Future<void> unlock(String password) async {
    final envelope = identityEnvelope;
    final uid = userId;
    if (envelope == null || uid == null) {
      throw const FormatException('No encrypted identity was saved.');
    }
    final material = await unlockForLogin(
      envelope: envelope,
      password: password,
      accountId: uid,
    );
    if (material.envelope['version'] != envelope['version'] ||
        material.envelope['keyProtection'] != envelope['keyProtection']) {
      await api.updateIdentityEnvelope(material.envelope);
      identityEnvelope = material.envelope;
      for (final account in savedAccounts) {
        if (account['userId'] == uid) account['identityEnvelope'] = material.envelope;
      }
      await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
      await _persistActive();
    }
    _destroyIdentity();
    identity = material.keyPair;
    await _storage.write(
      key: 'identityPrivateKey_$uid',
      value: base64Encode(material.privateKeyBytes),
    );
    await _storage.delete(key: _manualLockKey);
    notifyListeners();
  }

  void _destroyIdentity() {
    final current = identity;
    identity = null;
    current?.destroy();
  }

  Future<void> switchAccount(String targetId) async {
    await PushNotificationService.unregister(api);
    Map<String, dynamic>? account;
    for (final item in savedAccounts) {
      if (item['userId'] == targetId) {
        account = item;
        break;
      }
    }
    if (account == null) return;
    _destroyIdentity();
    token = account['token'] as String;
    username = account['username'] as String;
    userId = account['userId'] as String;
    photoUrl = account['photoUrl'] as String?;
    identityEnvelope = Map<String, dynamic>.from(
      account['identityEnvelope'] as Map,
    );
    api.token = token;
    await _persistActive();
    final savedPrivateKey = await _storage.read(
      key: 'identityPrivateKey_$targetId',
    );
    if (savedPrivateKey != null) {
      try {
        identity = await CryptoService.restoreIdentityFromPrivateBytes(
          identityEnvelope!,
          base64Decode(savedPrivateKey),
        );
      } catch (_) {
        await _storage.delete(key: 'identityPrivateKey_$targetId');
      }
    }
    notifyListeners();
  }

  Future<void> addAccount() async {
    await PushNotificationService.unregister(api);
    _destroyIdentity();
    token = null;
    username = null;
    userId = null;
    photoUrl = null;
    identityEnvelope = null;
    api.token = null;
    await _clearActiveSession();
    notifyListeners();
  }

  Future<void> signOut() async {
    await PushNotificationService.unregister(api);
    if (userId != null) {
      await _storage.delete(key: 'identityPrivateKey_$userId');
    }
    savedAccounts.removeWhere((account) => account['userId'] == userId);
    await _storage.write(key: _accountsKey, value: jsonEncode(savedAccounts));
    _destroyIdentity();
    token = null;
    username = null;
    userId = null;
    photoUrl = null;
    identityEnvelope = null;
    api.token = null;
    await _clearActiveSession();
    notifyListeners();
  }

  Future<void> _clearActiveSession() async {
    final previousUserId = userId;
    final keepSavedIdentity =
        previousUserId != null &&
        savedAccounts.any((account) => account['userId'] == previousUserId);
    token = null;
    username = null;
    userId = null;
    photoUrl = null;
    identityEnvelope = null;
    _destroyIdentity();
    api.token = null;
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'userId');
    await _storage.delete(key: 'identityEnvelope');
    if (previousUserId != null && !keepSavedIdentity) {
      await _storage.delete(key: 'identityPrivateKey_$previousUserId');
    }
    await _storage.delete(key: _manualLockKey);
  }

  Future<void> _persistActive() async {
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'userId', value: userId);
    if (userId != null) await _storage.write(key: 'profilePhotoUrl_$userId', value: photoUrl);
    await _storage.write(
      key: 'identityEnvelope',
      value: jsonEncode(identityEnvelope),
    );
  }

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    await _storage.write(key: 'pref_notifications', value: value.toString());
    notifyListeners();
  }

  Future<void> setSoundEffectsEnabled(bool value) async {
    soundEffectsEnabled = value;
    await _storage.write(key: 'pref_sound_effects', value: value.toString());
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool value) async {
    vibrationEnabled = value;
    await _storage.write(key: 'pref_vibration', value: value.toString());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _storage.write(
      key: 'pref_theme_mode',
      value: switch (value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    notifyListeners();
  }

  String _messageIndexKey(String uid, String chatId) =>
      'cc_msg_index_${uid}_$chatId';
  String _messageKey(String uid, String chatId, String messageId) =>
      'cc_msg_${uid}_${chatId}_$messageId';
  String _messageTombstoneKey(String uid, String chatId, String messageId) =>
      'cc_msg_tombstone_${uid}_${chatId}_$messageId';

  Future<void> _withCacheWriteLock(
    String uid,
    String chatId,
    Future<void> Function() operation,
  ) async {
    final key = '$uid:$chatId';
    final previous = _cacheWriteQueues[key] ?? Future<void>.value();
    final release = Completer<void>();
    final current = release.future;
    _cacheWriteQueues[key] = current;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed write must not permanently block later cache operations.
      }
      await operation();
    } finally {
      release.complete();
      if (identical(_cacheWriteQueues[key], current)) {
        _cacheWriteQueues.remove(key);
      }
    }
  }

  /// Persists only the encrypted envelope and delivery metadata. The receipt
  /// endpoint must not be called until this Future completes successfully.
  Future<void> saveCachedMessage(
    String chatId,
    Map<String, dynamic> message,
  ) async {
    final uid = userId;
    final id = message['id'];
    if (uid == null ||
        id is! String ||
        !_chatIdPattern.hasMatch(chatId) ||
        !_messageIdPattern.hasMatch(id)) {
      throw const FormatException('Invalid local message cache record.');
    }
    await _withCacheWriteLock(uid, chatId, () async {
      if (await _storage.read(key: _messageTombstoneKey(uid, chatId, id)) ==
          'true') {
        return;
      }
      await _writeCachedMessage(uid, chatId, message);
    });
  }

  Future<void> _writeCachedMessage(
    String uid,
    String chatId,
    Map<String, dynamic> message,
  ) async {
    final id = message['id'] as String;
    const allowed = [
      'id',
      'senderId',
      'format',
      'ciphertext',
      'nonce',
      'mac',
      'createdAt',
      'deliveryState',
      'deliveredTo',
      'readBy',
    ];
    final safe = <String, dynamic>{
      for (final field in allowed)
        if (message.containsKey(field)) field: message[field],
    };
    await _storage.write(
      key: _messageKey(uid, chatId, id),
      value: jsonEncode(safe),
    );

    final indexKey = _messageIndexKey(uid, chatId);
    final encodedIndex = await _storage.read(key: indexKey);
    List<String> ids = [];
    if (encodedIndex != null) {
      try {
        final decoded = jsonDecode(encodedIndex);
        if (decoded is List) {
          ids = decoded
              .whereType<String>()
              .where(_messageIdPattern.hasMatch)
              .toSet()
              .toList();
        }
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
    final uid = userId;
    if (uid == null || !_chatIdPattern.hasMatch(chatId)) return [];
    final encodedIndex = await _storage.read(
      key: _messageIndexKey(uid, chatId),
    );
    if (encodedIndex == null) return [];
    List<dynamic> decodedIds;
    try {
      final decoded = jsonDecode(encodedIndex);
      if (decoded is! List) return [];
      decodedIds = decoded;
    } catch (_) {
      return [];
    }
    final ids = decodedIds
        .whereType<String>()
        .where(_messageIdPattern.hasMatch)
        .toSet()
        .toList();
    final records = <Map<String, dynamic>>[];
    // Secure-storage platform-channel calls are expensive; bounded batches
    // reduce chat-open latency without flooding the Android keystore bridge.
    for (var start = 0; start < ids.length; start += 16) {
      final batch = ids.skip(start).take(16).toList();
      final encodedRecords = await Future.wait(
        batch.map((id) async {
          try {
            return await _storage.read(key: _messageKey(uid, chatId, id));
          } catch (_) {
            return null;
          }
        }),
      );
      for (final encoded in encodedRecords) {
        if (encoded == null) continue;
        try {
          final decoded = jsonDecode(encoded);
          if (decoded is Map) records.add(Map<String, dynamic>.from(decoded));
        } catch (_) {
          // Ignore corrupt cache entries; the next sync can recover the message.
        }
      }
    }
    records.sort(
      (a, b) => _asInt(a['createdAt']).compareTo(_asInt(b['createdAt'])),
    );
    return records;
  }

  Future<void> updateCachedMessage(
    String chatId,
    String messageId, {
    required String deliveryState,
    Map<String, dynamic>? serverMessage,
  }) async {
    final uid = userId;
    if (uid == null ||
        !_chatIdPattern.hasMatch(chatId) ||
        !_messageIdPattern.hasMatch(messageId)) {
      return;
    }
    await _withCacheWriteLock(uid, chatId, () async {
      if (await _storage.read(
            key: _messageTombstoneKey(uid, chatId, messageId),
          ) ==
          'true') {
        return;
      }
      final existing = await _storage.read(
        key: _messageKey(uid, chatId, messageId),
      );
      if (existing == null) return;
      late final Map<String, dynamic> message;
      try {
        message = Map<String, dynamic>.from(jsonDecode(existing) as Map);
      } catch (_) {
        return;
      }
      message['id'] = messageId;
      if (serverMessage != null) {
        for (final field in [
          'senderId',
          'format',
          'ciphertext',
          'nonce',
          'mac',
          'createdAt',
          'deliveredTo',
          'readBy',
        ]) {
          if (serverMessage.containsKey(field)) {
            message[field] = serverMessage[field];
          }
        }
      }
      message['deliveryState'] = deliveryState;
      await _writeCachedMessage(uid, chatId, message);
    });
  }

  Future<void> deleteCachedMessage(String chatId, String messageId) async {
    final uid = userId;
    if (uid == null ||
        !_chatIdPattern.hasMatch(chatId) ||
        !_messageIdPattern.hasMatch(messageId)) {
      return;
    }
    await _withCacheWriteLock(uid, chatId, () async {
      await _storage.write(
        key: _messageTombstoneKey(uid, chatId, messageId),
        value: 'true',
      );
      await _storage.delete(key: _messageKey(uid, chatId, messageId));
      final indexKey = _messageIndexKey(uid, chatId);
      final encoded = await _storage.read(key: indexKey);
      if (encoded == null) return;
      List<String> ids = [];
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) ids = decoded.whereType<String>().toList();
      } catch (_) {
        // Rebuild an empty index if the stored one is malformed.
      }
      ids.removeWhere((id) => id == messageId);
      await _storage.write(key: indexKey, value: jsonEncode(ids));
    });
  }

  Future<int> getCachedMessageCount() async {
    final uid = userId;
    if (uid == null) return 0;
    final all = await _storage.readAll();
    return all.keys
        .where(
          (key) => key.startsWith('cc_msg_${uid}_') && !key.contains('index'),
        )
        .length;
  }

  /// Exports encrypted message envelopes only. Plaintext is never part of the
  /// returned archive; DriveBackupService encrypts the whole archive again.
  Future<Map<String, dynamic>> exportEncryptedLocalArchive() async {
    final uid = userId;
    if (uid == null || identity == null || identity!.hasBeenDestroyed) {
      throw StateError(
        'Unlock your CrazeChat identity before backing up messages.',
      );
    }
    final all = await _storage.readAll();
    if (userId != uid || identity == null || identity!.hasBeenDestroyed) {
      throw StateError('The active CrazeChat account changed during backup.');
    }
    final prefix = 'cc_msg_index_${uid}_';
    final tombstonePrefix = 'cc_msg_tombstone_${uid}_';
    final chatIds =
        all.keys
            .where(
              (key) =>
                  key.startsWith(prefix) || key.startsWith(tombstonePrefix),
            )
            .map(
              (key) => key.startsWith(prefix)
                  ? key.substring(prefix.length)
                  : key.substring(
                      tombstonePrefix.length,
                      tombstonePrefix.length + 32,
                    ),
            )
            .where(_chatIdPattern.hasMatch)
            .toSet()
            .toList()
          ..sort();
    final chats = <Map<String, dynamic>>[];
    for (final chatId in chatIds) {
      if (userId != uid || identity == null || identity!.hasBeenDestroyed) {
        throw StateError('The active CrazeChat account changed during backup.');
      }
      final messages = await loadCachedMessages(chatId);
      final tombstones =
          all.keys
              .where((key) => key.startsWith('$tombstonePrefix${chatId}_'))
              .map(
                (key) =>
                    key.substring(tombstonePrefix.length + chatId.length + 1),
              )
              .where(_messageIdPattern.hasMatch)
              .toSet()
              .toList()
            ..sort();
      chats.add({
        'chatId': chatId,
        'messages': messages,
        'deletedMessageIds': tombstones,
      });
    }
    return {'version': 1, 'userId': uid, 'chats': chats};
  }

  /// Merges authenticated encrypted envelopes from Drive into this account's
  /// local cache. Existing local records win if a message ID is already stored.
  Future<int> mergeEncryptedLocalArchive(Map<String, dynamic> archive) async {
    final uid = userId;
    if (uid == null ||
        identity == null ||
        identity!.hasBeenDestroyed ||
        archive['version'] != 1 ||
        archive['userId'] != uid ||
        archive['chats'] is! List) {
      throw const FormatException(
        'This encrypted backup does not match the active CrazeChat account.',
      );
    }
    final rawChats = archive['chats'] as List;
    if (rawChats.length > 2000) {
      throw const FormatException(
        'The local backup contains too many conversations.',
      );
    }
    final validated =
        <
          ({
            String chatId,
            List<Map<String, dynamic>> messages,
            List<String> tombstones,
          })
        >[];
    var totalMessages = 0;
    for (final rawChat in rawChats) {
      if (rawChat is! Map) {
        throw const FormatException('Invalid conversation in local backup.');
      }
      final chatId = rawChat['chatId'];
      final rawMessages = rawChat['messages'];
      final rawTombstones = rawChat['deletedMessageIds'] ?? const [];
      if (chatId is! String ||
          !_chatIdPattern.hasMatch(chatId) ||
          rawMessages is! List ||
          rawTombstones is! List) {
        throw const FormatException('Invalid conversation in local backup.');
      }
      if (rawMessages.length > 100000 ||
          totalMessages + rawMessages.length > 200000) {
        throw const FormatException(
          'The local backup contains too many messages.',
        );
      }
      final messages = <Map<String, dynamic>>[];
      final tombstones = <String>{};
      for (final rawId in rawTombstones) {
        if (rawId is! String || !_messageIdPattern.hasMatch(rawId)) {
          throw const FormatException(
            'Invalid deletion marker in local backup.',
          );
        }
        tombstones.add(rawId);
      }
      for (final rawMessage in rawMessages) {
        if (rawMessage is! Map) {
          throw const FormatException('Invalid message in local backup.');
        }
        final message = Map<String, dynamic>.from(rawMessage);
        final id = message['id'];
        if (id is! String ||
            !_messageIdPattern.hasMatch(id) ||
            message['createdAt'] is! num) {
          throw const FormatException('Invalid message in local backup.');
        }
        if (tombstones.contains(id)) continue;
        CryptoService.validateMessageEnvelope(message);
        messages.add(message);
      }
      totalMessages += messages.length;
      validated.add((
        chatId: chatId,
        messages: messages,
        tombstones: tombstones.toList(),
      ));
    }

    var imported = 0;
    for (final chat in validated) {
      if (userId != uid || identity == null || identity!.hasBeenDestroyed) {
        throw StateError(
          'The active CrazeChat account changed during restore.',
        );
      }
      for (final id in chat.tombstones) {
        if (userId != uid || identity == null || identity!.hasBeenDestroyed) {
          throw StateError(
            'The active CrazeChat account changed during restore.',
          );
        }
        await deleteCachedMessage(chat.chatId, id);
      }
      final existing = (await loadCachedMessages(chat.chatId))
          .map((message) => message['id']?.toString())
          .whereType<String>()
          .toSet();
      for (final message in chat.messages) {
        if (userId != uid || identity == null || identity!.hasBeenDestroyed) {
          throw StateError(
            'The active CrazeChat account changed during restore.',
          );
        }
        final id = message['id'] as String;
        if (existing.add(id)) {
          await saveCachedMessage(chat.chatId, message);
          imported++;
        }
      }
    }
    return imported;
  }

  int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> lock() async {
    _destroyIdentity();
    notifyListeners();
    try {
      await _storage.write(key: _manualLockKey, value: 'true');
    } catch (_) {
      // The in-memory key is still destroyed if persistent storage is unavailable.
    }
  }
}
