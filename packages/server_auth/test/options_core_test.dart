import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthOptions preserves configured values and copyWith overrides', () {
    final base = AuthOptions<String>(
      providers: [CredentialsProvider()],
      basePath: '/identity',
      csrfKey: '_csrf',
      callbacks: AuthCallbacks<String>(redirect: (context) => context.url),
    );

    final updated = base.copyWith(
      basePath: '/auth',
      enforceCsrf: false,
      sessionStrategy: AuthSessionStrategy.jwt,
    );

    expect(base.providers, hasLength(1));
    expect(base.basePath, equals('/identity'));
    expect(updated.basePath, equals('/auth'));
    expect(updated.enforceCsrf, isFalse);
    expect(updated.sessionStrategy, equals(AuthSessionStrategy.jwt));
    expect(updated.callbacks.redirect, isNotNull);
  });
}
