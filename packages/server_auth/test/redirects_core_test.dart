import 'package:property_testing/property_testing.dart';
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

  test('sanitizeRedirectUrl rejects same-host different-port URLs', () {
    final sanitized = sanitizeRedirectUrl(
      'https://app.test:8443/profile',
      requestUri: Uri.parse('https://app.test/auth/signin'),
    );
    expect(sanitized, isNull);
  });

  test('sanitizeRedirectUrl allows the exact same custom port', () {
    final sanitized = sanitizeRedirectUrl(
      'https://app.test:8443/profile',
      requestUri: Uri.parse('https://app.test:8443/auth/signin'),
    );
    expect(sanitized, equals('https://app.test:8443/profile'));
  });

  test('sanitizeRedirectUrl rejects protocol-relative URLs', () {
    // `//evil.test/phish` must not pass the rooted-relative branch: browsers
    // resolve it as a cross-origin Location header (open redirect).
    final sanitized = sanitizeRedirectUrl(
      '//evil.test/phish',
      requestUri: Uri.parse('https://app.test/auth/signin'),
    );
    expect(sanitized, isNull);
  });

  test('sanitizeRedirectUrl rejects protocol-relative port variants', () {
    expect(
      sanitizeRedirectUrl(
        '//evil.test:8443/phish',
        requestUri: Uri.parse('https://app.test/auth/signin'),
      ),
      isNull,
    );
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

  test('sanitizeRedirectUrl rejects user-info on a trusted host', () {
    final requestUri = Uri.parse('https://app.test/auth/signin');
    expect(
      sanitizeRedirectUrl(
        'https://user:password@app.test/account',
        requestUri: requestUri,
      ),
      isNull,
    );
    expect(
      sanitizeRedirectUrl(
        'https://user%40example.test@app.test/account',
        requestUri: requestUri,
      ),
      isNull,
    );
  });

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

  test(
    'resolveAndSanitizeRedirectCandidate combines precedence with sanitization',
    () {
      final sanitized = resolveAndSanitizeRedirectCandidate(
        <String, dynamic>{'callbackUrl': 'https://app.test/one'},
        <String, String>{'callbackUrl': '/fallback'},
        requestUri: Uri.parse('https://app.test/auth/signin'),
      );
      expect(sanitized, equals('https://app.test/one'));
    },
  );

  test(
    'resolveAndSanitizeRedirectCandidate rejects cross-origin candidates',
    () {
      final sanitized = resolveAndSanitizeRedirectCandidate(
        <String, dynamic>{'callbackUrl': 'https://evil.test/one'},
        <String, String>{'callbackUrl': '/fallback'},
        requestUri: Uri.parse('https://app.test/auth/signin'),
      );
      expect(sanitized, isNull);
    },
  );

  test(
    'resolveAndSanitizeRedirectWithResolver resolves then sanitizes callback result',
    () async {
      final resolved = await resolveAndSanitizeRedirectWithResolver(
        <String, dynamic>{'callbackUrl': '/one'},
        <String, String>{},
        requestUri: Uri.parse('https://app.test/auth/signin'),
        resolveRedirect: (candidate) => '/two?from=${candidate ?? ''}',
      );

      expect(resolved, equals('/two?from=/one'));
    },
  );

  test(
    'resolveAndSanitizeRedirectWithResolver falls back to candidate when callback returns null',
    () async {
      final resolved = await resolveAndSanitizeRedirectWithResolver(
        <String, dynamic>{'callbackUrl': '/one'},
        <String, String>{'callbackUrl': '/two'},
        requestUri: Uri.parse('https://app.test/auth/signin'),
        resolveRedirect: (_) => null,
      );

      expect(resolved, equals('/one'));
    },
  );

  test(
    'resolveAndSanitizeRedirectWithResolver rejects cross-origin callback result',
    () async {
      final resolved = await resolveAndSanitizeRedirectWithResolver(
        <String, dynamic>{'callbackUrl': '/one'},
        <String, String>{},
        requestUri: Uri.parse('https://app.test/auth/signin'),
        resolveRedirect: (_) => 'https://evil.test/pwn',
      );

      expect(resolved, isNull);
    },
  );

  test(
    'respondWithSanitizedAuthRedirectOrSession prefers sanitized redirect',
    () async {
      final session = AuthSession(
        user: AuthUser(id: 'user-1'),
        expiresAt: null,
        strategy: AuthSessionStrategy.session,
      );
      final result = AuthResult(
        user: session.user,
        session: session,
        redirectUrl: '/dashboard',
      );
      var sessionCalled = false;

      final response = await respondWithSanitizedAuthRedirectOrSession<String>(
        result: result,
        requestUri: Uri.parse('https://app.test/auth/callback'),
        onRedirect: (redirectUrl) => 'redirect:$redirectUrl',
        onSession: (_) {
          sessionCalled = true;
          return 'session';
        },
      );

      expect(response, equals('redirect:/dashboard'));
      expect(sessionCalled, isFalse);
    },
  );

  test(
    'respondWithSanitizedAuthRedirectOrSession falls back to session when redirect is invalid',
    () async {
      final session = AuthSession(
        user: AuthUser(id: 'user-1'),
        expiresAt: null,
        strategy: AuthSessionStrategy.session,
      );
      final result = AuthResult(
        user: session.user,
        session: session,
        redirectUrl: 'https://evil.test/pwn',
      );
      var redirected = false;

      final response = await respondWithSanitizedAuthRedirectOrSession<String>(
        result: result,
        requestUri: Uri.parse('https://app.test/auth/callback'),
        onRedirect: (_) {
          redirected = true;
          return 'redirect';
        },
        onSession: (_) => 'session',
      );

      expect(response, equals('session'));
      expect(redirected, isFalse);
    },
  );

  test(
    'property: accepted redirects never escape the request origin',
    () async {
      final requestUri = Uri.parse('https://app.example.test/auth/signin');
      final candidates = Gen.frequency([
        (4, Chaos.string(minLength: 0, maxLength: 300)),
        (
          2,
          Gen.oneOf<String>([
            '',
            '//evil.example.test/steal',
            'https://evil.example.test/callback',
            'https://app.example.test.evil.example.test/callback',
            'https://user:password@app.example.test/account',
            'javascript:alert(1)',
            'data:text/html,<script>alert(1)</script>',
            'file:///etc/passwd',
            '\r\nLocation: https://evil.example.test',
          ]),
        ),
        (
          1,
          Gen.oneOf<String>([
            '/account',
            '/settings?tab=security',
            'https://app.example.test/account',
            'https://app.example.test:443/settings',
          ]),
        ),
      ]);

      final runner = PropertyTestRunner<String>(candidates, (candidate) {
        final sanitized = sanitizeRedirectUrl(
          candidate,
          requestUri: requestUri,
        );
        if (sanitized == null) return;

        final uri = Uri.parse(sanitized);
        expect(uri.userInfo, isEmpty, reason: candidate);
        if (uri.isAbsolute) {
          expect(uri.scheme, equals('https'), reason: candidate);
          expect(uri.host, equals('app.example.test'), reason: candidate);
          expect(uri.port, anyOf(0, 443), reason: candidate);
        } else {
          expect(uri.host, isEmpty, reason: candidate);
          expect(sanitized, startsWith('/'), reason: candidate);
        }
      }, PropertyConfig(numTests: 250, seed: 20260819));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _formatResult(result));
    },
  );
}

String _formatResult(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} tests passed';
  return 'Property failed after ${result.numTests} tests: '
      '${result.error}; input=${result.failingInput}; seed=${result.seed}';
}
