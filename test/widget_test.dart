import 'package:flutter_test/flutter_test.dart';
import 'package:crazechat/core.dart';

void main() {
  group('Core response helpers', () {
    test('converts JSON maps without losing keys', () {
      final value = asJsonMap({'ok': true, 'count': 2});
      expect(value['ok'], isTrue);
      expect(value['count'], 2);
    });

    test('normalizes arbitrary maps to string keys', () {
      final value = asJsonMap({1: 'one', 'two': 2});
      expect(value['1'], 'one');
      expect(value['two'], 2);
    });

    test('stringValue uses fallbacks for null and stringifies values', () {
      expect(stringValue(null, 'fallback'), 'fallback');
      expect(stringValue(12), '12');
      expect(stringValue('ready'), 'ready');
    });
  });
}
