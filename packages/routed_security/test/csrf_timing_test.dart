import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('security helpers', () {
    test('generateCsrfToken returns URL-safe random tokens', () {
      final one = generateCsrfToken();
      final two = generateCsrfToken();

      expect(one, isNotEmpty);
      expect(two, isNotEmpty);
      expect(one, isNot(equals(two)));
      expect(RegExp(r'^[A-Za-z0-9_-]+=?$').hasMatch(one), isTrue);
    });

    test('timingSafeEquals compares equal and unequal values', () {
      expect(timingSafeEquals('abc123', 'abc123'), isTrue);
      expect(timingSafeEquals('abc123', 'abc124'), isFalse);
      expect(timingSafeEquals('abc123', 'abc1234'), isFalse);
    });
  });
}
