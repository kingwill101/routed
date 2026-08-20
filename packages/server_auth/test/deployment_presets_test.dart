import 'dart:async';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('typed deployment usage examples', () {
    test('local development composes explicit providers and plugins', () {
      final plugin = _ExamplePlugin();

      final AuthDeployment<String> deployment =
          AuthDeploymentPresets.localDevelopment<String>(
            providers: [CredentialsProvider()],
            plugins: [plugin],
            trustedOrigins: [Uri.parse('http://localhost:3000')],
          );

      expect(deployment.options.store, isA<InMemoryAuthStore>());
      expect(deployment.options.storeMode, AuthStoreMode.ephemeral);
      expect(deployment.options.providers.single.id, 'credentials');
      expect(deployment.options.plugins.single, same(plugin));
      expect(deployment.options.cookiePolicy.secure, isFalse);
      expect(deployment.options.enforceCsrf, isTrue);
      expect(deployment.options.browserProtection.trustedOrigins, [
        'http://localhost:3000',
      ]);
      expect(
        deployment.configuration.session.strategy,
        AuthSessionStrategy.session,
      );
      expect(deployment.proxyPolicy.trustsForwardedHeaders, isFalse);
      expect(deployment.requiresDurableStore, isFalse);
    });

    test('secure session production keeps security choices visible', () {
      final store = _DurableAuthStore();
      final limiter = _AllowAllRateLimiter();
      final delivery = _delivery();
      final boundary = AuthProductionBoundary(
        trustedOrigins: [Uri.parse('https://app.example.com')],
        proxyPolicy: AuthProxyPolicy.trusted(
          proxies: ['10.0.0.0/8'],
          headers: ['CF-Connecting-IP'],
        ),
      );

      final AuthDeployment<String> deployment =
          AuthDeploymentPresets.secureSessionProduction<String>(
            store: store,
            providers: [CredentialsProvider()],
            plugins: [_ExamplePlugin()],
            boundary: boundary,
            lifecycleDelivery: delivery,
            rateLimiter: limiter,
            requireVerifiedEmail: true,
            sessionMaxAge: const Duration(days: 14),
            sessionUpdateAge: const Duration(hours: 12),
            cookieDomain: 'example.com',
          );

      expect(deployment.options.store, same(store));
      expect(deployment.options.storeMode, AuthStoreMode.durable);
      expect(deployment.options.sessionStrategy, AuthSessionStrategy.session);
      expect(deployment.options.cookiePolicy.httpOnly, isTrue);
      expect(deployment.options.cookiePolicy.secure, isTrue);
      expect(deployment.options.cookiePolicy.domain, 'example.com');
      expect(deployment.options.browserProtection.requireOrigin, isTrue);
      expect(deployment.options.browserProtection.requireContentType, isTrue);
      expect(deployment.options.requireVerifiedEmail, isTrue);
      expect(deployment.options.rateLimiter, same(limiter));
      expect(
        deployment.options.passwordResetSender,
        same(delivery.passwordReset),
      );
      expect(deployment.options.emailChangeSender, same(delivery.emailChange));
      expect(
        deployment.options.accountDeletionSender,
        same(delivery.accountDeletion),
      );
      expect(deployment.configuration.session.maxAge, const Duration(days: 14));
      expect(deployment.proxyPolicy.proxies, ['10.0.0.0/8']);
      expect(deployment.requiresDurableStore, isTrue);
    });

    test('JWT API production configures issuance and adapter verification', () {
      final AuthDeployment<String> deployment =
          AuthDeploymentPresets.jwtApiProduction<String>(
            store: _DurableAuthStore(),
            providers: [CredentialsProvider()],
            plugins: [_ExamplePlugin()],
            boundary: _directBoundary(),
            lifecycleDelivery: _delivery(),
            rateLimiter: _AllowAllRateLimiter(),
            requireVerifiedEmail: true,
            exposeJwtTokenInSessionResponse: true,
            jwtSecret: 'a-production-secret-with-at-least-32-bytes',
            issuer: Uri.parse('https://identity.example.com'),
            audience: ['orders-api'],
            tokenMaxAge: const Duration(minutes: 20),
          );

      expect(deployment.options.sessionStrategy, AuthSessionStrategy.jwt);
      expect(
        deployment.options.jwtOptions.issuer,
        'https://identity.example.com',
      );
      expect(deployment.options.jwtOptions.audience, ['orders-api']);
      expect(deployment.options.jwtOptions.secure, isTrue);
      expect(deployment.options.exposeJwtTokenInSessionResponse, isTrue);
      expect(deployment.configuration.jwt.enabled, isTrue);
      expect(deployment.configuration.jwt.algorithms, ['HS256']);
      expect(deployment.configuration.jwt.inlineKeys, hasLength(1));
      expect(
        deployment.configuration.session.strategy,
        AuthSessionStrategy.jwt,
      );
    });

    test('service preset returns the exact API-key plugin for middleware', () {
      final apiKeyStore = _DurableApiKeyStore();

      final AuthApiKeyDeployment<String> deployment =
          AuthDeploymentPresets.serviceApiKeyProduction<String>(
            store: _DurableAuthStore(),
            apiKeyStore: apiKeyStore,
            providers: [CredentialsProvider()],
            plugins: [_ExamplePlugin()],
            boundary: _directBoundary(),
            lifecycleDelivery: _delivery(),
            rateLimiter: _AllowAllRateLimiter(),
            requireVerifiedEmail: true,
            allowSessionExchange: false,
            keyPrefix: 'orders',
          );

      expect(deployment.apiKeys.store, same(apiKeyStore));
      expect(deployment.apiKeys.keyPrefix, 'orders');
      expect(deployment.apiKeys.sessionExchangeEnabled, isFalse);
      expect(deployment.options.plugins.first, same(deployment.apiKeys));
      expect(deployment.options.plugins.map((plugin) => plugin.id), [
        authApiKeyPluginId,
        'example',
      ]);
      expect(deployment.options.sessionStrategy, AuthSessionStrategy.session);
    });
  });

  group('production preset validation', () {
    test('requires exact HTTPS origins', () {
      expect(
        () => AuthProductionBoundary(
          trustedOrigins: const [],
          proxyPolicy: const AuthProxyPolicy.direct(),
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthProductionBoundary(
          trustedOrigins: [Uri.parse('http://app.example.com')],
          proxyPolicy: const AuthProxyPolicy.direct(),
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthProductionBoundary(
          trustedOrigins: [Uri.parse('https://app.example.com/path')],
          proxyPolicy: const AuthProxyPolicy.direct(),
        ),
        throwsArgumentError,
      );
    });

    test('requires an explicit bounded trusted-proxy network', () {
      expect(
        () => AuthProxyPolicy.trusted(proxies: const []),
        throwsArgumentError,
      );
      expect(
        () => AuthProxyPolicy.trusted(proxies: ['0.0.0.0/0']),
        throwsArgumentError,
      );
      expect(
        () => AuthProxyPolicy.trusted(proxies: ['not-a-network']),
        throwsArgumentError,
      );
      expect(
        () => AuthProxyPolicy.trusted(
          proxies: ['10.0.0.0/8'],
          headers: ['X-Forwarded-For\r\nX-Injected: yes'],
        ),
        throwsArgumentError,
      );

      final policy = AuthProxyPolicy.trusted(proxies: ['2001:db8::/32']);
      expect(policy.proxies, ['2001:db8::/32']);
    });

    test('rejects ephemeral core and API-key stores', () {
      expect(
        () => AuthDeploymentPresets.secureSessionProduction<String>(
          store: InMemoryAuthStore(),
          providers: [CredentialsProvider()],
          boundary: _directBoundary(),
          lifecycleDelivery: _delivery(),
          rateLimiter: _AllowAllRateLimiter(),
          requireVerifiedEmail: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthDeploymentPresets.serviceApiKeyProduction<String>(
          store: _DurableAuthStore(),
          apiKeyStore: InMemoryAuthApiKeyStore(),
          providers: [CredentialsProvider()],
          boundary: _directBoundary(),
          lifecycleDelivery: _delivery(),
          rateLimiter: _AllowAllRateLimiter(),
          requireVerifiedEmail: true,
          allowSessionExchange: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects weak shared secrets and invalid JWT audiences', () {
      AuthDeployment<String> build({
        required String secret,
        Iterable<String> audience = const ['api'],
      }) => AuthDeploymentPresets.jwtApiProduction<String>(
        store: _DurableAuthStore(),
        providers: [CredentialsProvider()],
        boundary: _directBoundary(),
        lifecycleDelivery: _delivery(),
        rateLimiter: _AllowAllRateLimiter(),
        requireVerifiedEmail: true,
        exposeJwtTokenInSessionResponse: false,
        jwtSecret: secret,
        issuer: Uri.parse('https://identity.example.com'),
        audience: audience,
      );

      expect(() => build(secret: 'too-short'), throwsArgumentError);
      expect(
        () => build(
          secret: 'a-production-secret-with-at-least-32-bytes',
          audience: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthDeploymentPresets.jwtApiProduction<String>(
          store: _DurableAuthStore(),
          providers: [CredentialsProvider()],
          boundary: _directBoundary(),
          lifecycleDelivery: _delivery(),
          rateLimiter: _AllowAllRateLimiter(),
          requireVerifiedEmail: true,
          exposeJwtTokenInSessionResponse: false,
          jwtSecret: 'only-forty-bytes-is-not-enough-for-hs512',
          issuer: Uri.parse('https://identity.example.com'),
          audience: ['api'],
          algorithm: 'HS512',
        ),
        throwsArgumentError,
      );
    });

    test('lifecycle delivery must be explicitly enabled or disabled', () {
      const disabled = AuthLifecycleDelivery<String>.disabled();
      final deployment = AuthDeploymentPresets.secureSessionProduction<String>(
        store: _DurableAuthStore(),
        providers: [CredentialsProvider()],
        boundary: _directBoundary(),
        lifecycleDelivery: disabled,
        rateLimiter: _AllowAllRateLimiter(),
        requireVerifiedEmail: true,
      );

      expect(disabled.enabled, isFalse);
      expect(deployment.options.passwordResetSender, isNull);
      expect(deployment.options.emailChangeSender, isNull);
      expect(deployment.options.accountDeletionSender, isNull);
    });

    test('rejects duplicate plugin IDs before runtime boot', () {
      expect(
        () => AuthDeploymentPresets.localDevelopment<String>(
          providers: [CredentialsProvider()],
          plugins: [_ExamplePlugin(), _ExamplePlugin()],
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthDeploymentPresets.serviceApiKeyProduction<String>(
          store: _DurableAuthStore(),
          apiKeyStore: _DurableApiKeyStore(),
          providers: [CredentialsProvider()],
          plugins: [AuthApiKeyPlugin<String>(store: _DurableApiKeyStore())],
          boundary: _directBoundary(),
          lifecycleDelivery: _delivery(),
          rateLimiter: _AllowAllRateLimiter(),
          requireVerifiedEmail: true,
          allowSessionExchange: false,
        ),
        throwsArgumentError,
      );
    });
  });
}

AuthProductionBoundary _directBoundary() => AuthProductionBoundary(
  trustedOrigins: [Uri.parse('https://app.example.com')],
  proxyPolicy: const AuthProxyPolicy.direct(),
);

AuthLifecycleDelivery<String> _delivery() =>
    AuthLifecycleDelivery<String>.enabled(
      passwordReset: (_) async {},
      emailChange: (_) async {},
      accountDeletion: (_) async {},
    );

final class _AllowAllRateLimiter implements AuthRateLimiter<String> {
  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<String> request) =>
      const AuthRateLimitDecision.allow();
}

final class _ExamplePlugin implements AuthServerPlugin<String> {
  @override
  String get id => 'example';

  @override
  void configure(AuthServerPluginContext<String> context) {}
}

final class _DurableAuthStore implements AuthStore {
  final InMemoryAuthStore _delegate = InMemoryAuthStore();

  @override
  AuthAccountStore get accounts => _delegate.accounts;

  @override
  AuthCredentialStore get credentials => _delegate.credentials;

  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      _delegate.deviceAuthorizations;

  @override
  AuthEmailChangeTokenStore get emailChangeTokens =>
      _delegate.emailChangeTokens;

  @override
  AuthEmailOtpStore get emailOtps => _delegate.emailOtps;

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
}

final class _DurableApiKeyStore implements AuthApiKeyStore {
  final InMemoryAuthApiKeyStore _delegate = InMemoryAuthApiKeyStore();

  @override
  FutureOr<AuthApiKeyRecord> create(AuthApiKeyRecord record) =>
      _delegate.create(record);

  @override
  FutureOr<void> deleteForUser(String userId) =>
      _delegate.deleteForUser(userId);

  @override
  FutureOr<AuthApiKeyRecord?> findById(String id) => _delegate.findById(id);

  @override
  FutureOr<List<AuthApiKeyRecord>> listForUser(String userId) =>
      _delegate.listForUser(userId);

  @override
  FutureOr<AuthApiKeyRecord?> revokeForUser(
    String userId,
    String id, {
    DateTime? revokedAt,
  }) => _delegate.revokeForUser(userId, id, revokedAt: revokedAt);

  @override
  FutureOr<AuthApiKeyRecord?> rotateForUser({
    required String userId,
    required String id,
    required AuthApiKeyRecord replacement,
    DateTime? revokedAt,
  }) => _delegate.rotateForUser(
    userId: userId,
    id: id,
    replacement: replacement,
    revokedAt: revokedAt,
  );

  @override
  FutureOr<AuthApiKeyRecord?> touchIfActive(String id, DateTime lastUsedAt) =>
      _delegate.touchIfActive(id, lastUsedAt);
}
