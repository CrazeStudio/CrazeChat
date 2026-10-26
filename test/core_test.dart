import 'package:flutter_test/flutter_test.dart';
import 'package:crazechat/core.dart';

void main() {
  group('P-256 coordinate normalization', () {
    test('removes an old leading sign-padding zero from 33-byte coordinates', () {
      final coordinate = <int>[0, ...List<int>.generate(32, (index) => index)];
      expect(normalizeP256Coordinate(coordinate), List<int>.generate(32, (index) => index));
    });

    test('left-pads short unsigned coordinates to exactly 32 bytes', () {
      expect(normalizeP256Coordinate([1, 2, 3]), [
        ...List<int>.filled(29, 0), 1, 2, 3,
      ]);
    });

    test('rejects a coordinate that cannot fit in 32 bytes', () {
      expect(
        () => normalizeP256Coordinate([1, ...List<int>.filled(32, 2)]),
        throwsFormatException,
      );
    });
  });


  group('CrazeChat API DTO parsing', () {
    test('parses indexed API messages and delivery metadata', () {
      final message = ChatMessage.fromJson({
        'id': 'message-1',
        'chatId': 'chat-1',
        'senderUid': 'user-a',
        'senderUsername': 'alice',
        'receiverId': 'user-b',
        'ciphertext': 'cipher',
        'nonce': 'nonce',
        'createdAt': '2026-10-26T12:30:00.000Z',
        'expiresAt': '2026-10-27T12:30:00.000Z',
        'editedAt': '',
        'pinned': true,
        'reactions': {'user-b': '❤️'},
        'receipts': {'user-b': {'seenAt': '2026-10-26T12:31:00.000Z'}},
      });

      expect(message.id, 'message-1');
      expect(message.chatId, 'chat-1');
      expect(message.senderUid, 'user-a');
      expect(message.pinned, isTrue);
      expect(message.reactions['user-b'], '❤️');
      expect(message.receipts.containsKey('user-b'), isTrue);
      expect(message.expiresAt, isNotNull);
    });

    test('parses compact API plaintext messages without marking them encrypted', () {
      final message = ChatMessage.fromJson({
        'id': 'plain-message',
        'chatId': 'chat-plain',
        'senderUid': 'user-a',
        'text': 'Hello from compact route',
        'encrypted': false,
        'createdAt': '2026-10-26T12:30:00.000Z',
      });

      expect(message.text, 'Hello from compact route');
      expect(message.encrypted, isFalse);
      expect(message.ciphertext, isEmpty);
    });

    test('parses group chat membership and key version', () {
      final chat = ChatRecord.fromJson({
        'id': 'group-1',
        'title': 'Study group',
        'isGroup': true,
        'createdBy': 'user-a',
        'createdAt': '2026-10-26T10:00:00.000Z',
        'groupKeyVersion': 4,
        'pinnedMessageId': 'message-2',
        'members': {
          'user-a': {'role': 'owner'},
          'user-b': {'role': 'member'},
        },
      });

      expect(chat.id, 'group-1');
      expect(chat.isGroup, isTrue);
      expect(chat.createdBy, 'user-a');
      expect(chat.groupKeyVersion, 4);
      expect(chat.memberIds, containsAll(['user-a', 'user-b']));
      expect(chat.pinnedMessageId, 'message-2');
    });

    test('uses legacy timestamp data if createdAt is absent', () {
      final message = ChatMessage.fromJson({
        'id': 'legacy-message',
        'timestamp': 1793016000000,
        'ciphertext': 'legacy',
        'isPinned': true,
      });

      expect(message.createdAt.millisecondsSinceEpoch, 1793016000000);
      expect(message.pinned, isTrue);
    });
  });
}
