import 'package:http/http.dart' as http;
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

  test('resolveAuthOptions merges providers and applies overrides', () {
    final adapter = AuthAdapter();
    final tokenStore = InMemoryAuthVerificationTokenStore();
    final httpClient = http.Client();
    final base = AuthOptions<String>(
      providers: const <AuthProvider>[
        AuthProvider(
          id: 'credentials',
          name: 'Credentials',
          type: AuthProviderType.credentials,
        ),
      ],
      sessionStrategy: AuthSessionStrategy.session,
    );

    final resolved = resolveAuthOptions<String>(
      options: base,
      configuredProviders: const <AuthProvider>[
        AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      ],
      adapter: adapter,
      tokenStore: tokenStore,
      httpClient: httpClient,
      sessionStrategy: AuthSessionStrategy.jwt,
      sessionMaxAge: const Duration(hours: 1),
      sessionUpdateAge: const Duration(minutes: 5),
    );

    expect(resolved.providers.map((provider) => provider.id), <String>[
      'credentials',
      'google',
    ]);
    expect(identical(resolved.adapter, adapter), isTrue);
    expect(identical(resolved.tokenStore, tokenStore), isTrue);
    expect(identical(resolved.httpClient, httpClient), isTrue);
    expect(resolved.sessionStrategy, AuthSessionStrategy.jwt);
    expect(resolved.sessionMaxAge, const Duration(hours: 1));
    expect(resolved.sessionUpdateAge, const Duration(minutes: 5));
  });

  test('resolveAuthOptions preserves explicit option-level values', () {
    final explicitClient = http.Client();
    final explicitStore = InMemoryAuthVerificationTokenStore();
    final explicitMaxAge = const Duration(minutes: 30);
    final explicitUpdateAge = const Duration(minutes: 2);
    final base = AuthOptions<String>(
      providers: const <AuthProvider>[
        AuthProvider(
          id: 'credentials',
          name: 'Credentials',
          type: AuthProviderType.credentials,
        ),
      ],
      httpClient: explicitClient,
      tokenStore: explicitStore,
      sessionMaxAge: explicitMaxAge,
      sessionUpdateAge: explicitUpdateAge,
    );

    final resolved = resolveAuthOptions<String>(
      options: base,
      httpClient: http.Client(),
      tokenStore: InMemoryAuthVerificationTokenStore(),
      sessionMaxAge: const Duration(hours: 1),
      sessionUpdateAge: const Duration(minutes: 10),
    );

    expect(identical(resolved.httpClient, explicitClient), isTrue);
    expect(identical(resolved.tokenStore, explicitStore), isTrue);
    expect(resolved.sessionMaxAge, explicitMaxAge);
    expect(resolved.sessionUpdateAge, explicitUpdateAge);
  });
}
