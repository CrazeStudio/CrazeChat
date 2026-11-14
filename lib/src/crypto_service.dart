import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class IdentityMaterial {
  const IdentityMaterial({
    required this.keyPair,
    required this.envelope,
    required this.privateKeyBytes,
  });
  final KeyPair keyPair;
  final Map<String, dynamic> envelope;
  final List<int> privateKeyBytes;
}

class CryptoService {
  static const _identityAad = 'CrazeChat/identity-key/v1';
  static const _localBackupFormat = 'cc-local-backup-v1';
  // Keep the wire format identical to the Cloudflare API validator:
  // AES-GCM nonce = 12 bytes, authentication tag = 16 bytes.
  static final _aes = AesGcm.with256bits(nonceLength: 12);
  static final _localBackupKdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _identityKdf = Argon2id(
    memory: 32 * 1024,
    parallelism: 1,
    iterations: 2,
    hashLength: 32,
  );

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static List<int> _decodeExact(
    Map<String, dynamic> envelope,
    String field,
    int length,
  ) {
    final value = envelope[field];
    if (value is! String) {
      throw FormatException('Encrypted identity field "$field" is missing.');
    }
    try {
      final decoded = base64Decode(value);
      if (decoded.length != length) {
        throw FormatException(
          'Encrypted identity field "$field" must contain exactly $length bytes.',
        );
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException(
        'Encrypted identity field "$field" is not valid base64.',
      );
    }
  }

  static void validateIdentityEnvelope(Map<String, dynamic> envelope) {
    if (![1, 2, 3].contains(envelope['version']) || envelope['kdf'] != 'Argon2id') {
      throw const FormatException(
        'Unsupported encrypted identity version or KDF.',
      );
    }
    _decodeExact(envelope, 'salt', 16);
    _decodeExact(envelope, 'nonce', 12);
    _decodeExact(envelope, 'mac', 16);
    _decodeExact(envelope, 'publicKey', 32);
    final ciphertext = envelope['ciphertext'];
    if (ciphertext is! String || ciphertext.isEmpty) {
      throw const FormatException('Encrypted identity ciphertext is missing.');
    }
    try {
      if (base64Decode(ciphertext).isEmpty) {
        throw const FormatException('Encrypted identity ciphertext is empty.');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Encrypted identity ciphertext is not valid base64.',
      );
    }
  }

  static Future<IdentityMaterial> createIdentity(String password, {bool separatePassphrase = false}) async {
    final keyPair = await X25519().newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBase64 = base64Encode(publicKey.bytes);
    final salt = _randomBytes(16);
    final wrappingKey = await _identityKdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = await _aes.encrypt(
      privateBytes,
      secretKey: wrappingKey,
      aad: utf8.encode('$_identityAad:$publicKeyBase64'),
    );
    final envelope = <String, dynamic>{
      'version': separatePassphrase ? 2 : 3,
      'keyProtection': separatePassphrase ? 'separate-passphrase-v2' : 'account-password-v3',
      'kdf': 'Argon2id',
      'kdfMemoryKiB': 32768,
      'kdfIterations': 2,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'publicKey': publicKeyBase64,
    };
    validateIdentityEnvelope(envelope);
    return IdentityMaterial(
      keyPair: keyPair,
      envelope: envelope,
      privateKeyBytes: privateBytes,
    );
  }

  static Future<KeyPair> restoreIdentityFromPrivateBytes(
    Map<String, dynamic> envelope,
    List<int> privateBytes,
  ) async {
    validateIdentityEnvelope(envelope);
    if (privateBytes.length != 32) {
      throw const FormatException(
        'Stored private identity key has an invalid length.',
      );
    }
    final publicKey = SimplePublicKey(
      _decodeExact(envelope, 'publicKey', 32),
      type: KeyPairType.x25519,
    );
    return SimpleKeyPairData(
      privateBytes,
      publicKey: publicKey,
      type: KeyPairType.x25519,
    );
  }

  static Future<IdentityMaterial> unlockIdentityMaterial(
    Map<String, dynamic> envelope,
    String password,
  ) async {
    validateIdentityEnvelope(envelope);
    final publicKeyBase64 = envelope['publicKey'] as String;
    final salt = _decodeExact(envelope, 'salt', 16);
    final wrappingKey = await _identityKdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: _decodeExact(envelope, 'nonce', 12),
      mac: Mac(_decodeExact(envelope, 'mac', 16)),
    );
    final privateBytes = await _aes.decrypt(
      box,
      secretKey: wrappingKey,
      aad: utf8.encode('$_identityAad:$publicKeyBase64'),
    );
    final publicKey = SimplePublicKey(
      _decodeExact(envelope, 'publicKey', 32),
      type: KeyPairType.x25519,
    );
    final keyPair = SimpleKeyPairData(
      privateBytes,
      publicKey: publicKey,
      type: KeyPairType.x25519,
    );
    return IdentityMaterial(
      keyPair: keyPair,
      envelope: envelope,
      privateKeyBytes: privateBytes,
    );
  }

  /// Re-wraps the account identity using its account password. The private
  /// key is never sent to the backend; the password is still sent separately
  /// as the normal HTTPS login credential for server-side authentication.
  static Future<IdentityMaterial> rewrapUnlockedIdentity({
    required KeyPair identity,
    required String password,
    bool separatePassphrase = false,
  }) async {
    final keyData = await identity.extract();
    if (keyData is! SimpleKeyPairData || keyData.type != KeyPairType.x25519) {
      throw const FormatException('The CrazeChat identity is not an X25519 key pair.');
    }
    final privateBytes = keyData.bytes;
    final publicKey = keyData.publicKey.bytes;
    final publicKeyBase64 = base64Encode(publicKey);
    final salt = _randomBytes(16);
    final wrappingKey = await _identityKdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = await _aes.encrypt(
      privateBytes,
      secretKey: wrappingKey,
      aad: utf8.encode('$_identityAad:$publicKeyBase64'),
    );
    final nextEnvelope = <String, dynamic>{
      'version': separatePassphrase ? 2 : 3,
      'keyProtection': separatePassphrase ? 'separate-passphrase-v2' : 'account-password-v3',
      'kdf': 'Argon2id',
      'kdfMemoryKiB': 32768,
      'kdfIterations': 2,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'publicKey': publicKeyBase64,
    };
    validateIdentityEnvelope(nextEnvelope);
    return IdentityMaterial(
      keyPair: identity,
      envelope: nextEnvelope,
      privateKeyBytes: privateBytes,
    );
  }

  static Future<KeyPair> unlockIdentity(
    Map<String, dynamic> envelope,
    String password,
  ) async => (await unlockIdentityMaterial(envelope, password)).keyPair;

  static Future<String> fingerprintPublicKey(String publicKeyBase64) async {
    final publicKey = base64Decode(publicKeyBase64);
    if (publicKey.length != 32) {
      throw const FormatException('Contact public key must contain exactly 32 bytes.');
    }
    final digest = await Sha256().hash(publicKey);
    final hex = digest.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return RegExp(r'.{1,4}').allMatches(hex).map((match) => match.group(0)!).join(' ');
  }

  static Future<SecretKey> deriveChatKey({
    required KeyPair myKeyPair,
    required String peerPublicKey,
    required String chatId,
  }) async {
    final remote = SimplePublicKey(
      base64Decode(peerPublicKey),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: remote,
    );
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(chatId),
      info: utf8.encode('CrazeChat/direct-message/v1'),
    );
  }

  /// Adds an independent authenticated-encryption layer to a local folder archive.
  /// The wrapping key is derived from the account identity key, so only a
  /// device that has unlocked the same identity can open the archive.
  static Future<Map<String, dynamic>> encryptLocalBackup({
    required List<int> archiveBytes,
    required KeyPair identity,
    required String userId,
  }) async {
    if (userId.isEmpty) {
      throw const FormatException('A CrazeChat account is required.');
    }
    final key = await _localBackupKey(identity, userId);
    final aad = utf8.encode('$_localBackupFormat:$userId');
    final box = await _aes.encrypt(archiveBytes, secretKey: key, aad: aad);
    return {
      'format': _localBackupFormat,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<List<int>> decryptLocalBackup({
    required Map<String, dynamic> envelope,
    required KeyPair identity,
    required String userId,
  }) async {
    if (envelope['format'] != _localBackupFormat || userId.isEmpty) {
      throw const FormatException(
        'Unsupported or invalid CrazeChat local backup.',
      );
    }
    final nonce = _decodeBase64Field(envelope, 'nonce', exactLength: 12);
    final ciphertext = _decodeBase64Field(envelope, 'ciphertext');
    final mac = _decodeBase64Field(envelope, 'mac', exactLength: 16);
    if (ciphertext.isEmpty) {
      throw const FormatException('Local backup is empty.');
    }
    final key = await _localBackupKey(identity, userId);
    return _aes.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
      aad: utf8.encode('$_localBackupFormat:$userId'),
    );
  }

  static Future<SecretKey> _localBackupKey(
    KeyPair identity,
    String userId,
  ) async {
    final keyData = await identity.extract();
    if (keyData is! SimpleKeyPairData || keyData.type != KeyPairType.x25519) {
      throw const FormatException(
        'The CrazeChat identity is not an X25519 key pair.',
      );
    }
    final privateBytes = keyData.bytes;
    return _localBackupKdf.deriveKey(
      secretKey: SecretKey(privateBytes),
      nonce: utf8.encode('CrazeChat/local-backup-salt/v1:$userId'),
      info: utf8.encode('CrazeChat/local-folder-backup/v1'),
    );
  }

  static List<int> _decodeBase64Field(
    Map<String, dynamic> envelope,
    String field, {
    int? exactLength,
  }) {
    final value = envelope[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('Encrypted field "$field" is missing.');
    }
    late final List<int> decoded;
    try {
      decoded = base64Decode(value);
    } on FormatException {
      throw FormatException('Encrypted field "$field" is not valid base64.');
    }
    if (exactLength != null && decoded.length != exactLength) {
      throw FormatException(
        'Encrypted field "$field" must contain exactly $exactLength bytes.',
      );
    }
    return decoded;
  }

  static void validateMessageEnvelope(Map<String, dynamic> message) {
    if (message['format'] != 'cc-e2ee-v1' ||
        message['senderId'] is! String ||
        (message['senderId'] as String).isEmpty) {
      throw const FormatException('Unsupported or invalid encrypted message.');
    }
    if (_decodeBase64Field(message, 'ciphertext').isEmpty) {
      throw const FormatException('Encrypted message ciphertext is empty.');
    }
    _decodeBase64Field(message, 'nonce', exactLength: 12);
    _decodeBase64Field(message, 'mac', exactLength: 16);
  }

  static Future<Map<String, String>> encryptMessage({
    required String text,
    required SecretKey chatKey,
    required String chatId,
    required String senderId,
  }) async {
    final box = await _aes.encrypt(
      utf8.encode(text),
      secretKey: chatKey,
      aad: utf8.encode('CrazeChat/message/v1:$chatId:$senderId'),
    );
    return {
      'format': 'cc-e2ee-v1',
      'ciphertext': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<String> decryptMessage({
    required Map<String, dynamic> message,
    required SecretKey chatKey,
    required String chatId,
  }) async {
    validateMessageEnvelope(message);
    final senderId = message['senderId'] as String;
    final box = SecretBox(
      base64Decode(message['ciphertext'] as String),
      nonce: base64Decode(message['nonce'] as String),
      mac: Mac(base64Decode(message['mac'] as String)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: chatKey,
      aad: utf8.encode('CrazeChat/message/v1:$chatId:$senderId'),
    );
    return utf8.decode(clear);
  }
}
