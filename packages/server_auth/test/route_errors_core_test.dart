import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('keeps bounded auth identifiers public', () {
    expect(sanitizeAuthErrorCode('invalid_credentials'), 'invalid_credentials');
    expect(sanitizeAuthErrorCode('callback_failed'), 'callback_failed');
  });

  test('replaces diagnostic strings with a generic code', () {
    expect(
      sanitizeAuthErrorCode('/srv/secrets/auth-production.key'),
      'auth_error',
    );
    expect(sanitizeAuthErrorCode('database password: secret'), 'auth_error');
    expect(sanitizeAuthErrorCode(''), 'auth_error');
    expect(sanitizeAuthErrorCode(null), 'auth_error');
  });
}
