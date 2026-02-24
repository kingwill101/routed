import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('extractBearerToken', () {
    test('extracts token for matching prefix', () {
      expect(extractBearerToken('Bearer token-123'), equals('token-123'));
    });

    test('returns null for missing or invalid values', () {
      expect(extractBearerToken(null), isNull);
      expect(extractBearerToken(''), isNull);
      expect(extractBearerToken('Basic abc'), isNull);
      expect(extractBearerToken('Bearer   '), isNull);
    });

    test('supports custom prefix', () {
      expect(extractBearerToken('Token abc', prefix: 'Token '), equals('abc'));
    });

    test('supports case-insensitive matching', () {
      expect(
        extractBearerToken('bearer lower', caseSensitive: false),
        equals('lower'),
      );
      expect(extractBearerToken('bearer lower'), isNull);
    });

    test('uses full value when prefix is empty', () {
      expect(
        extractBearerToken('  raw-token  ', prefix: ''),
        equals('raw-token'),
      );
    });
  });
}
