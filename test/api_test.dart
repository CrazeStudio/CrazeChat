import 'package:flutter_test/flutter_test.dart';
import 'package:crazechat/src/api.dart';

void main() {
  group('CrazeChatApi input validation', () {
    final api = CrazeChatApi();
    final validId = List<String>.filled(32, 'a').join();

    test('rejects malformed conversation and message identifiers', () {
      expect(() => api.getMessages('not-an-id'), throwsA(isA<ApiException>()));
      expect(
        () => api.sendMessage(validId, {'id': 'not-an-id'}),
        throwsA(isA<ApiException>()),
      );
    });

    test('enforces message page bounds and acknowledgement status', () {
      expect(
        () => api.getMessages(validId, limit: 101),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => api.acknowledgeMessages(
          validId,
          messageIds: [validId],
          status: 'sent',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('creates unique-format 128-bit lowercase hexadecimal message IDs', () {
      final first = api.createMessageId();
      final second = api.createMessageId();
      expect(first, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(second, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(second, isNot(first));
    });

    test('rejects insecure remote origins before REST or WebSocket credentials are sent', () async {
      final insecure = CrazeChatApi(
        baseUrl: 'http://attacker.example',
        sharedKey: 'test-shared-key',
        token: 'test-user-token',
      );
      await expectLater(insecure.listChats(), throwsA(isA<ApiException>()));
      await expectLater(
        insecure.connectRealtime(validId),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'rejects API origins containing credentials, paths, queries or fragments',
      () async {
        for (final origin in [
          'https://user:pass@api.example',
          'https://api.example/db',
          'https://api.example/?',
          'https://api.example/#',
        ]) {
          final configured = CrazeChatApi(
            baseUrl: origin,
            sharedKey: 'test-shared-key',
          );
          await expectLater(
            configured.listChats(),
            throwsA(isA<ApiException>()),
            reason: 'Rejected unsafe origin: $origin',
          );
        }
      },
    );
  });
}
