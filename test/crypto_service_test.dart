import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crazechat/src/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identity envelope matches the API byte-length contract', () async {
    final material = await CryptoService.createIdentity(
      'correct horse battery staple 2026',
    );
    final envelope = material.envelope;
    expect(envelope['version'], 2);
    expect(envelope['keyProtection'], 'separate-passphrase-v2');
    expect(envelope['kdf'], 'Argon2id');
    expect(base64Decode(envelope['salt'] as String), hasLength(16));
    expect(base64Decode(envelope['nonce'] as String), hasLength(12));
    expect(base64Decode(envelope['ciphertext'] as String), isNotEmpty);
    expect(base64Decode(envelope['mac'] as String), hasLength(16));
    expect(base64Decode(envelope['publicKey'] as String), hasLength(32));
    expect(
      () => CryptoService.validateIdentityEnvelope({
        ...envelope,
        'nonce': base64Encode(List<int>.filled(11, 0)),
      }),
      throwsFormatException,
    );
  });

  test('password protects and restores the private identity key', () async {
    final material = await CryptoService.createIdentity(
      'correct horse battery staple 2026',
    );
    final restored = await CryptoService.unlockIdentity(
      material.envelope,
      'correct horse battery staple 2026',
    );
    final originalPublic =
        await material.keyPair.extractPublicKey() as SimplePublicKey;
    final restoredPublic = await restored.extractPublicKey() as SimplePublicKey;
    expect(restoredPublic.bytes, originalPublic.bytes);
    await expectLater(
      CryptoService.unlockIdentity(material.envelope, 'wrong password'),
      throwsA(anything),
    );
  });

  test('identity encryption passphrase is independent and can be rotated locally', () async {
    final material = await CryptoService.createIdentity('private encryption passphrase 2026');
    await expectLater(
      CryptoService.unlockIdentity(material.envelope, 'different account password 2026'),
      throwsA(anything),
    );
    final rotated = await CryptoService.rewrapUnlockedIdentity(
      identity: material.keyPair,
      encryptionPassphrase: 'new independent encryption passphrase 2027',
    );
    expect(rotated.envelope['version'], 2);
    final unlockedRotated = await CryptoService.unlockIdentity(
      rotated.envelope,
      'new independent encryption passphrase 2027',
    );
    expect(await unlockedRotated.extractPublicKey(), isA<SimplePublicKey>());
    await expectLater(
      CryptoService.unlockIdentity(
        rotated.envelope,
        'private encryption passphrase 2026',
      ),
      throwsA(anything),
    );
    final legacyEnvelope = <String, dynamic>{...material.envelope, 'version': 1}
      ..remove('keyProtection');
    final unlockedLegacy = await CryptoService.unlockIdentity(
      legacyEnvelope,
      'private encryption passphrase 2026',
    );
    expect(await unlockedLegacy.extractPublicKey(), isA<SimplePublicKey>());
    final fingerprint = await CryptoService.fingerprintPublicKey(
      material.envelope['publicKey'] as String,
    );
    expect(fingerprint.replaceAll(' ', ''), matches(RegExp(r'^[A-F0-9]{64}$')));
  });

  test(
    'secure-storage restore reconstructs the same identity from private bytes',
    () async {
      final material = await CryptoService.createIdentity(
        'correct horse battery staple 2026',
      );
      final restored = await CryptoService.restoreIdentityFromPrivateBytes(
        material.envelope,
        material.privateKeyBytes,
      );
      final originalPublic =
          await material.keyPair.extractPublicKey() as SimplePublicKey;
      final restoredPublic =
          await restored.extractPublicKey() as SimplePublicKey;
      expect(restoredPublic.bytes, originalPublic.bytes);
    },
  );

  test(
    'Local folder archive is double-encrypted with the account identity key',
    () async {
      final alice = await CryptoService.createIdentity(
        'alice secure password 2026',
      );
      final bob = await CryptoService.createIdentity(
        'bob secure password 2026',
      );
      final archive = utf8.encode('{"messages":["ciphertext-only"]}');
      final envelope = await CryptoService.encryptLocalBackup(
        archiveBytes: archive,
        identity: alice.keyPair,
        userId: 'alice-user-id',
      );
      expect(envelope['format'], 'cc-local-backup-v1');
      expect(
        await CryptoService.decryptLocalBackup(
          envelope: envelope,
          identity: alice.keyPair,
          userId: 'alice-user-id',
        ),
        archive,
      );
      final restoredAlice = await CryptoService.restoreIdentityFromPrivateBytes(
        alice.envelope,
        alice.privateKeyBytes,
      );
      expect(
        await CryptoService.decryptLocalBackup(
          envelope: envelope,
          identity: restoredAlice,
          userId: 'alice-user-id',
        ),
        archive,
      );
      await expectLater(
        CryptoService.decryptLocalBackup(
          envelope: envelope,
          identity: bob.keyPair,
          userId: 'alice-user-id',
        ),
        throwsA(anything),
      );
      await expectLater(
        CryptoService.decryptLocalBackup(
          envelope: envelope,
          identity: alice.keyPair,
          userId: 'different-user-id',
        ),
        throwsA(anything),
      );
      final ciphertext = base64Decode(envelope['ciphertext'] as String);
      ciphertext[0] ^= 1;
      await expectLater(
        CryptoService.decryptLocalBackup(
          envelope: {...envelope, 'ciphertext': base64Encode(ciphertext)},
          identity: alice.keyPair,
          userId: 'alice-user-id',
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'two participants derive the same chat key and decrypt a message',
    () async {
      final alice = await CryptoService.createIdentity(
        'alice secure password 2026',
      );
      final bob = await CryptoService.createIdentity(
        'bob secure password 2026',
      );
      final aliceKey = await CryptoService.deriveChatKey(
        myKeyPair: alice.keyPair,
        peerPublicKey: bob.envelope['publicKey'] as String,
        chatId: 'conversation-test-1',
      );
      final bobKey = await CryptoService.deriveChatKey(
        myKeyPair: bob.keyPair,
        peerPublicKey: alice.envelope['publicKey'] as String,
        chatId: 'conversation-test-1',
      );
      final encrypted = await CryptoService.encryptMessage(
        text: 'hello encrypted world',
        chatKey: aliceKey,
        chatId: 'conversation-test-1',
        senderId: 'alice',
      );
      CryptoService.validateMessageEnvelope({
        ...encrypted,
        'senderId': 'alice',
      });
      expect(
        () => CryptoService.validateMessageEnvelope({
          ...encrypted,
          'senderId': 'alice',
          'nonce': base64Encode(List<int>.filled(11, 0)),
        }),
        throwsFormatException,
      );
      final clear = await CryptoService.decryptMessage(
        message: {...encrypted, 'senderId': 'alice'},
        chatKey: bobKey,
        chatId: 'conversation-test-1',
      );
      expect(clear, 'hello encrypted world');
    },
  );
}
