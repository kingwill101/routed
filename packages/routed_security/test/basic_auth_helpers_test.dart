import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('basic auth helpers', () {
    test('parses valid basic auth header', () {
      final creds = parseBasicAuthHeader('Basic dXNlcjpwYXNz'); // user:pass
      expect(creds, isNotNull);
      expect(creds!.username, 'user');
      expect(creds.password, 'pass');
    });

    test('returns null for malformed header', () {
      expect(parseBasicAuthHeader(null), isNull);
      expect(parseBasicAuthHeader('Bearer token'), isNull);
      expect(parseBasicAuthHeader('Basic invalid@@'), isNull);
    });

    test('validates parsed credentials against account map', () {
      final creds = const BasicAuthCredentials(
        username: 'admin',
        password: 'x',
      );
      final accounts = <String, String>{'admin': 'x'};
      expect(validateBasicAuthCredentials(creds, accounts), isTrue);
      expect(
        validateBasicAuthCredentials(
          const BasicAuthCredentials(username: 'admin', password: 'y'),
          accounts,
        ),
        isFalse,
      );
    });
  });
}
