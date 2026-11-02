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
  // Keep the wire format identical to the Cloudflare API validator:
  // AES-GCM nonce = 12 bytes, authentication tag = 16 bytes.
  static final _aes = AesGcm.with256bits(nonceLength: 12);
  static final _identityKdf = Argon2id(memory: 32 * 1024, parallelism: 1, iterations: 2, hashLength: 32);

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static List<int> _decodeExact(Map<String, dynamic> envelope, String field, int length) {
    final value = envelope[field];
    if (value is! String) throw FormatException('Encrypted identity field "$field" is missing.');
    try {
      final decoded = base64Decode(value);
      if (decoded.length != length) {
        throw FormatException('Encrypted identity field "$field" must contain exactly $length bytes.');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException('Encrypted identity field "$field" is not valid base64.');
    }
  }

  static void validateIdentityEnvelope(Map<String, dynamic> envelope) {
    if (envelope['version'] != 1 || envelope['kdf'] != 'Argon2id') {
      throw const FormatException('Unsupported encrypted identity version or KDF.');
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
      throw const FormatException('Encrypted identity ciphertext is not valid base64.');
    }
  }

  static Future<IdentityMaterial> createIdentity(String password) async {
    final keyPair = await X25519().newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBase64 = base64Encode(publicKey.bytes);
    final salt = _randomBytes(16);
    final wrappingKey = await _identityKdf.deriveKeyFromPassword(password: password, nonce: salt);
    final box = await _aes.encrypt(
      privateBytes,
      secretKey: wrappingKey,
      aad: utf8.encode('$_identityAad:$publicKeyBase64'),
    );
    final envelope = <String, dynamic>{
      'version': 1,
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
      throw const FormatException('Stored private identity key has an invalid length.');
    }
    final publicKey = SimplePublicKey(
      _decodeExact(envelope, 'publicKey', 32),
      type: KeyPairType.x25519,
    );
    return SimpleKeyPairData(privateBytes, publicKey: publicKey, type: KeyPairType.x25519);
  }

  static Future<IdentityMaterial> unlockIdentityMaterial(
    Map<String, dynamic> envelope,
    String password,
  ) async {
    validateIdentityEnvelope(envelope);
    final publicKeyBase64 = envelope['publicKey'] as String;
    final salt = _decodeExact(envelope, 'salt', 16);
    final wrappingKey = await _identityKdf.deriveKeyFromPassword(password: password, nonce: salt);
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

  static Future<KeyPair> unlockIdentity(
    Map<String, dynamic> envelope,
    String password,
  ) async => (await unlockIdentityMaterial(envelope, password)).keyPair;

  static Future<SecretKey> deriveChatKey({
    required KeyPair myKeyPair,
    required String peerPublicKey,
    required String chatId,
  }) async {
    final remote = SimplePublicKey(base64Decode(peerPublicKey), type: KeyPairType.x25519);
    final sharedSecret = await X25519().sharedSecretKey(keyPair: myKeyPair, remotePublicKey: remote);
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(chatId),
      info: utf8.encode('CrazeChat/direct-message/v1'),
    );
  }

  static Future<Map<String, String>> encryptMessage({
    required String text, required SecretKey chatKey,
    required String chatId, required String senderId,
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
    if (message['format'] != 'cc-e2ee-v1') throw const FormatException('Unknown message format.');
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
