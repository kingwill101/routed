import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('resolveCsrfToken returns existing token when present', () {
    final token = resolveCsrfToken(
      existingToken: 'existing-token',
      generateToken: () => 'generated-token',
    );

    expect(token, equals('existing-token'));
  });

  test('resolveCsrfToken generates token when missing', () {
    final token = resolveCsrfToken(
      existingToken: null,
      generateToken: () => 'generated-token',
    );

    expect(token, equals('generated-token'));
  });

  test('validateCsrfToken checks expected and presented tokens', () {
    expect(validateCsrfToken(expectedToken: 'abc', headerToken: 'abc'), isTrue);
    expect(validateCsrfToken(expectedToken: 'abc', formToken: 'abc'), isTrue);
    expect(
      validateCsrfToken(expectedToken: 'abc', headerToken: 'bad'),
      isFalse,
    );
    expect(validateCsrfToken(expectedToken: '', headerToken: 'abc'), isFalse);
    expect(validateCsrfToken(expectedToken: 'abc'), isFalse);
  });

  test('validateCsrfToken bypasses validation when disabled', () {
    expect(validateCsrfToken(expectedToken: null, enforce: false), isTrue);
  });
}
