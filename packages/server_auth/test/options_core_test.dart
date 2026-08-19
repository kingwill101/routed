import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('requires an explicit ephemeral mode for in-memory stores', () {
    expect(
      () => AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
      ),
      throwsArgumentError,
    );
    expect(
      () => AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: CallbackAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      ),
      throwsArgumentError,
    );
  });

  test('rejects callback-backed test stores from runtime options', () {
    expect(
      () => AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: CallbackAuthStore(),
      ),
      throwsArgumentError,
    );
    expect(
      () => AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: CallbackAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      ),
      throwsArgumentError,
    );
  });

  test('rejects empty, padded, and duplicate provider IDs', () {
    AuthOptions<String> options(List<AuthProvider> providers) {
      return AuthOptions<String>(
        providers: providers,
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      );
    }

    expect(
      () => options([
        AuthProvider(id: '', name: 'Empty', type: AuthProviderType.oauth),
      ]),
      throwsArgumentError,
    );
    expect(
      () => options([
        AuthProvider(
          id: ' google',
          name: 'Padded',
          type: AuthProviderType.oauth,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => options([
        AuthProvider(
          id: 'google',
          name: 'Google',
          type: AuthProviderType.oauth,
        ),
        AuthProvider(
          id: 'google',
          name: 'Google duplicate',
          type: AuthProviderType.oidc,
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('freezes the configured provider list', () {
    final options = AuthOptions<String>(
      providers: [CredentialsProvider()],
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
    );

    expect(
      () => options.providers.add(
        AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      ),
      throwsUnsupportedError,
    );
  });

  test('requireDurableStore rejects an explicitly ephemeral configuration', () {
    final options = AuthOptions<String>(
      providers: const <AuthProvider>[],
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
    );

    expect(options.requireDurableStore, throwsStateError);
  });

  test('rejects a non-positive OAuth challenge lifetime', () {
    expect(
      () => AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        oauthChallengeTtl: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('rejects a non-positive password-reset lifetime', () {
    expect(
      () => AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        passwordResetTtl: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('AuthOptions preserves configured values and copyWith overrides', () {
    Future<void> passwordResetSender(
      AuthPasswordResetRequest<String> _,
    ) async {}
    final base = AuthOptions<String>(
      providers: [CredentialsProvider()],
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      basePath: '/identity',
      csrfKey: '_csrf',
      browserProtection: const AuthBrowserProtectionOptions(
        allowedOrigins: ['https://app.example'],
      ),
      passwordPolicy: const PasswordPolicy(minimumLength: 16),
      passwordResetSender: passwordResetSender,
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
    expect(updated.passwordPolicy.minimumLength, equals(16));
    expect(updated.passwordResetSender, same(passwordResetSender));
    expect(
      base.browserProtection.allowedOrigins,
      equals(['https://app.example']),
    );
    expect(updated.callbacks.redirect, isNotNull);
  });

  test('resolveAuthOptions merges providers and applies overrides', () {
    final store = InMemoryAuthStore();
    final httpClient = http.Client();
    final base = AuthOptions<String>(
      providers: const <AuthProvider>[
        AuthProvider(
          id: 'credentials',
          name: 'Credentials',
          type: AuthProviderType.credentials,
        ),
      ],
      store: store,
      storeMode: AuthStoreMode.ephemeral,
      sessionStrategy: AuthSessionStrategy.session,
    );

    final resolved = resolveAuthOptions<String>(
      options: base,
      configuredProviders: const <AuthProvider>[
        AuthProvider(id: 'google', name: 'Google', type: AuthProviderType.oidc),
      ],
      store: store,
      httpClient: httpClient,
      sessionStrategy: AuthSessionStrategy.jwt,
      sessionMaxAge: const Duration(hours: 1),
      sessionUpdateAge: const Duration(minutes: 5),
    );

    expect(resolved.providers.map((provider) => provider.id), <String>[
      'credentials',
      'google',
    ]);
    expect(identical(resolved.store, store), isTrue);
    expect(identical(resolved.httpClient, httpClient), isTrue);
    expect(resolved.sessionStrategy, AuthSessionStrategy.jwt);
    expect(resolved.sessionMaxAge, const Duration(hours: 1));
    expect(resolved.sessionUpdateAge, const Duration(minutes: 5));
  });

  test('resolveAuthOptions preserves explicit option-level values', () {
    final explicitClient = http.Client();
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
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      httpClient: explicitClient,
      sessionMaxAge: explicitMaxAge,
      sessionUpdateAge: explicitUpdateAge,
    );

    final resolved = resolveAuthOptions<String>(
      options: base,
      httpClient: http.Client(),
      sessionMaxAge: const Duration(hours: 1),
      sessionUpdateAge: const Duration(minutes: 10),
    );

    expect(identical(resolved.httpClient, explicitClient), isTrue);
    expect(resolved.sessionMaxAge, explicitMaxAge);
    expect(resolved.sessionUpdateAge, explicitUpdateAge);
  });
}
