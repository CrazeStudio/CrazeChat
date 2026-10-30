import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class IdentityMaterial {
  const IdentityMaterial({required this.keyPair, required this.envelope});
  final KeyPair keyPair;
  final Map<String, dynamic> envelope;
}

class CryptoService {
  static const _identityAad = 'CrazeChat/identity-key/v1';
  static final _aes = AesGcm.with256bits();
  static final _identityKdf = Argon2id(memory: 32 * 1024, parallelism: 1, iterations: 2, hashLength: 32);

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
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
      aad: utf8.encode(_identityAad + ':' + publicKeyBase64),
    );
    return IdentityMaterial(
      keyPair: keyPair,
      envelope: {
        'version': 1,
        'kdf': 'Argon2id',
        'kdfMemoryKiB': 32768,
        'kdfIterations': 2,
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
        'publicKey': publicKeyBase64,
      },
    );
  }

  static Future<KeyPair> unlockIdentity(Map<String, dynamic> envelope, String password) async {
    if (envelope['version'] != 1 || envelope['kdf'] != 'Argon2id' || envelope['publicKey'] is! String) {
      throw const FormatException('Unsupported encrypted identity format.');
    }
    final publicKeyBase64 = envelope['publicKey'] as String;
    final salt = base64Decode(envelope['salt'] as String);
    final wrappingKey = await _identityKdf.deriveKeyFromPassword(password: password, nonce: salt);
    final box = SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final privateBytes = await _aes.decrypt(
      box,
      secretKey: wrappingKey,
      aad: utf8.encode(_identityAad + ':' + publicKeyBase64),
    );
    final publicKey = SimplePublicKey(base64Decode(publicKeyBase64), type: KeyPairType.x25519);
    return SimpleKeyPairData(privateBytes, publicKey: publicKey, type: KeyPairType.x25519);
  }

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