import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('baseUrlFromUri uses defaults when scheme/host are missing', () {
    final uri = Uri(path: '/login');
    expect(baseUrlFromUri(uri), equals('http://localhost'));
  });

  test('baseUrlFromUri keeps custom ports', () {
    expect(
      baseUrlFromUri(Uri.parse('https://app.test:443/auth')),
      equals('https://app.test'),
    );
    expect(
      baseUrlFromUri(Uri.parse('http://app.test:8080/auth')),
      equals('http://app.test:8080'),
    );
  });

  test('sanitizeRedirectUrl allows rooted relative paths', () {
    final sanitized = sanitizeRedirectUrl(
      '/dashboard',
      requestUri: Uri.parse('https://app.test/auth/signin'),
    );
    expect(sanitized, equals('/dashboard'));
  });

  test('sanitizeRedirectUrl rejects non-rooted relative paths', () {
    final sanitized = sanitizeRedirectUrl(
      'dashboard',
      requestUri: Uri.parse('https://app.test/auth/signin'),
    );
    expect(sanitized, isNull);
  });

  test('sanitizeRedirectUrl allows same-origin absolute URLs', () {
    final sanitized = sanitizeRedirectUrl(
      'https://app.test/profile',
      requestUri: Uri.parse('https://app.test/auth/signin'),
    );
    expect(sanitized, equals('https://app.test/profile'));
  });

  test('sanitizeRedirectUrl rejects cross-origin absolute URLs', () {
    final sanitized = sanitizeRedirectUrl(
      'https://evil.test/profile',
      requestUri: Uri.parse('https://app.test/auth/signin'),
    );
    expect(sanitized, isNull);
  });

  test(
    'sanitizeRedirectUrl uses fallback host/scheme when requestUri omits them',
    () {
      final sanitized = sanitizeRedirectUrl(
        'https://app.test/profile',
        requestUri: Uri(path: '/auth/signin'),
        fallbackHost: 'app.test',
        fallbackScheme: 'https',
      );
      expect(sanitized, equals('https://app.test/profile'));
    },
  );

  test('resolveRedirectCandidate applies payload/query precedence', () {
    expect(
      resolveRedirectCandidate(
        <String, dynamic>{'callbackUrl': '/one', 'redirect': '/two'},
        <String, String>{'callbackUrl': '/three'},
      ),
      equals('/one'),
    );

    expect(
      resolveRedirectCandidate(
        <String, dynamic>{'redirect': '/two'},
        <String, String>{'callbackUrl': '/three'},
      ),
      equals('/two'),
    );

    expect(
      resolveRedirectCandidate(<String, dynamic>{}, <String, String>{
        'callbackUrl': '/three',
      }),
      equals('/three'),
    );
  });

  test(
    'resolveRedirectCandidate keeps empty callback payload over fallback',
    () {
      expect(
        resolveRedirectCandidate(
          <String, dynamic>{'callbackUrl': '', 'redirect': '/two'},
          <String, String>{'callbackUrl': '/three'},
        ),
        equals(''),
      );
    },
  );
}
