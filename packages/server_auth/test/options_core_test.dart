import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('runtime posture', () {
    test('ephemeral storage selects explicit local-development defaults', () {
      final options = AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      );

      expect(options.runtimeMode, AuthRuntimeMode.localDevelopment);
      expect(options.productionBoundary, isNull);
      expect(options.cookiePolicy.secure, isFalse);
      expect(options.accountPolicy.maxLoginAttempts, 10);
      expect(options.browserProtection.requireOrigin, isFalse);
    });

    test('durable storage requires an explicit production boundary', () {
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
        ),
        throwsArgumentError,
      );
    });

    test('production derives coherent secure defaults', () {
      final boundary = _productionBoundary();
      final options = AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: _DurableAuthStore(),
        productionBoundary: boundary,
        rateLimiter: _AllowAllRateLimiter(),
      );

      expect(options.runtimeMode, AuthRuntimeMode.production);
      expect(options.productionBoundary, same(boundary));
      expect(options.cookiePolicy.secure, isTrue);
      expect(options.cookiePolicy.httpOnly, isTrue);
      expect(options.accountPolicy.requireEmailVerification, isTrue);
      expect(options.accountPolicy.allowUnverifiedSignIn, isFalse);
      expect(options.browserProtection.requireOrigin, isTrue);
      expect(options.browserProtection.enforceFetchMetadata, isTrue);
      expect(options.browserProtection.enforceReferrer, isTrue);
      expect(options.browserProtection.requireContentType, isTrue);
      expect(options.browserProtection.trustedOrigins, [
        'https://app.example.com',
      ]);
    });

    test('production requires an explicit rate limiter', () {
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
          productionBoundary: _productionBoundary(),
        ),
        throwsArgumentError,
      );
    });

    test('production rejects insecure browser and cookie overrides', () {
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
          productionBoundary: _productionBoundary(),
          browserProtection: const AuthBrowserProtectionOptions(),
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
          productionBoundary: _productionBoundary(),
          cookiePolicy: AuthCookiePolicy.development,
        ),
        throwsArgumentError,
      );
    });

    test('production browser origins exactly match the typed boundary', () {
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
          productionBoundary: _productionBoundary(),
          browserProtection: AuthBrowserProtectionOptions.production(
            trustedOrigins: const <String>[
              'https://app.example.com',
              'https://unexpected.example.com',
            ],
          ),
        ),
        throwsArgumentError,
      );

      final options = AuthOptions<String>(
        providers: const <AuthProvider>[],
        store: _DurableAuthStore(),
        productionBoundary: _productionBoundary(),
        rateLimiter: _AllowAllRateLimiter(),
        browserProtection: const AuthBrowserProtectionOptions(
          allowedOrigins: <String>['https://app.example.com'],
          requireOrigin: true,
          enforceReferrer: true,
          requireContentType: true,
        ),
      );

      expect(options.runtimeMode, AuthRuntimeMode.production);
    });

    test('production JWT sessions require algorithm-sized secrets', () {
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
          productionBoundary: _productionBoundary(),
          rateLimiter: _AllowAllRateLimiter(),
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(secret: 'too-short'),
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: _DurableAuthStore(),
          productionBoundary: _productionBoundary(),
          rateLimiter: _AllowAllRateLimiter(),
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(
            secret: 'a-production-secret-with-at-least-32-bytes',
            secure: false,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('local options reject production-only boundary state', () {
      expect(
        () => AuthOptions<String>(
          providers: const <AuthProvider>[],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          runtimeMode: AuthRuntimeMode.localDevelopment,
          productionBoundary: _productionBoundary(),
        ),
        throwsArgumentError,
      );
    });
  });

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

  test('preserves verified-email policy through option merges', () {
    final options = AuthOptions<String>(
      providers: const <AuthProvider>[],
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      requireVerifiedEmail: true,
    );

    expect(options.copyWith().requireVerifiedEmail, isTrue);
    expect(
      options.copyWith(requireVerifiedEmail: false).requireVerifiedEmail,
      isFalse,
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

  test('resolveAuthOptions derives mode for a replacement store', () {
    final base = AuthOptions<String>(
      providers: [CredentialsProvider()],
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
    );
    final durable = _DurableAuthStore();

    final resolved = resolveAuthOptions<String>(options: base, store: durable);

    expect(resolved.store, same(durable));
    expect(resolved.storeMode, AuthStoreMode.durable);
  });

  test('WebAuthn requires only its optional persistence capability', () {
    final store = _DurableAuthStore();
    final provider = WebAuthnProvider(
      getUserInfo: (_, _, _) => null,
      getRelyingParty: (_, _) => const WebAuthnRelyingParty(
        id: 'example.com',
        name: 'Example',
        origin: 'https://example.com',
      ),
    );

    expect(
      () => AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: [provider],
          store: store,
          productionBoundary: _productionBoundary(),
          rateLimiter: _AllowAllObjectRateLimiter(),
          plugins: [WebAuthnPlugin<Object>(provider: provider)],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('AuthWebAuthnStoreCapabilities'),
        ),
      ),
    );
  });
}

final class _AllowAllRateLimiter implements AuthRateLimiter<String> {
  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<String> request) =>
      const AuthRateLimitDecision.allow();
}

final class _AllowAllObjectRateLimiter implements AuthRateLimiter<Object> {
  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<Object> request) =>
      const AuthRateLimitDecision.allow();
}

AuthProductionBoundary _productionBoundary() => AuthProductionBoundary(
  trustedOrigins: [Uri.parse('https://app.example.com')],
  proxyPolicy: const AuthProxyPolicy.direct(),
);

final class _DurableAuthStore implements AuthStore {
  final InMemoryAuthStore _delegate = InMemoryAuthStore();

  @override
  AuthEmailChangeTokenStore get emailChangeTokens =>
      _delegate.emailChangeTokens;

  @override
  AuthAccountStore get accounts => _delegate.accounts;

  @override
  AuthCredentialStore get credentials => _delegate.credentials;

  @override
  AuthJwtVersionStore get jwtVersions => _delegate.jwtVersions;

  @override
  AuthOAuthChallengeStore get oauthChallenges => _delegate.oauthChallenges;

  @override
  AuthPasswordResetTokenStore get passwordResetTokens =>
      _delegate.passwordResetTokens;

  @override
  AuthSessionStore get sessions => _delegate.sessions;

  @override
  AuthUserStore get users => _delegate.users;

  @override
  AuthVerificationTokenStore get verificationTokens =>
      _delegate.verificationTokens;

  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      _delegate.deviceAuthorizations;

  @override
  AuthEmailOtpStore get emailOtps => _delegate.emailOtps;
}
