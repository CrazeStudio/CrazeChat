import 'package:flutter_test/flutter_test.dart';
import 'package:crazechat/src/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('password protects and restores the private identity key', () async {
    final material = await CryptoService.createIdentity('correct horse battery staple 2026');
    final restored = await CryptoService.unlockIdentity(material.envelope, 'correct horse battery staple 2026');
    final originalPublic = await material.keyPair.extractPublicKey();
    final restoredPublic = await restored.extractPublicKey();
    expect(restoredPublic.bytes, originalPublic.bytes);
    await expectLater(
      CryptoService.unlockIdentity(material.envelope, 'wrong password'),
      throwsA(anything),
    );
  });

  test('two participants derive the same chat key and decrypt a message', () async {
    final alice = await CryptoService.createIdentity('alice secure password 2026');
    final bob = await CryptoService.createIdentity('bob secure password 2026');
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
      text: 'hello encrypted world', chatKey: aliceKey,
      chatId: 'conversation-test-1', senderId: 'alice',
    );
    final clear = await CryptoService.decryptMessage(
      message: {...encrypted, 'senderId': 'alice'},
      chatKey: bobKey, chatId: 'conversation-test-1',
    );
    expect(clear, 'hello encrypted world');
  });
}