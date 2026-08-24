import 'dart:io' show SameSite;

import 'package:routed/routed.dart';

import 'embedded_views.dart';

/// Typed application wiring shared by the local server, tests, and Worker.
///
/// The durable store is supplied by the host entrypoint. Cloudflare provides
/// a D1-backed store, while tests can provide another `AuthStore` implementation
/// without changing the application composition. Local development selects
/// the auth preset's own ephemeral store.
final class AppConfig {
  AppConfig({
    required Iterable<ServiceProvider> providers,
    this.engineConfig,
    RuntimeContext? runtime,
    Iterable<EngineOpt> options = const [],
  }) : providers = List<ServiceProvider>.unmodifiable(providers),
       runtime = runtime ?? RuntimeContext(),
       options = List<EngineOpt>.unmodifiable(options);

  final List<ServiceProvider> providers;
  final RuntimeContext runtime;
  final EngineConfig? engineConfig;
  final List<EngineOpt> options;

  Engine buildEngine() => Engine(
    config: engineConfig,
    runtime: runtime,
    providers: providers,
    options: options,
  );
}

/// Builds the typed provider graph for the application.
///
/// Keep secrets, origins, and persistence bindings at this boundary. Routes
/// should depend on the configured services, not on Cloudflare or SQLite
/// details.
AppConfig config({
  required AuthStore store,
  AuthApiKeyStore? apiKeyStore,
  required Uri origin,
  required String sessionKey,
  Iterable<AuthProvider> socialProviders = const [],
  RateLimitService? rateLimitService,
  bool localDevelopment = false,
}) {
  if (sessionKey.trim().isEmpty) {
    throw ArgumentError.value(
      sessionKey,
      'sessionKey',
      'must be provided through a secret binding',
    );
  }

  final configuredRateLimitService =
      rateLimitService ??
      (localDevelopment
          ? RateLimitService(const [])
          : createRateLimitService());
  final authProviders = <AuthProvider>[
    CredentialsProvider(),
    ...socialProviders,
  ];
  final apiKeys = AuthApiKeyPlugin<EngineContext>(
    store: apiKeyStore ?? InMemoryAuthApiKeyStore(),
    sessionExchangeEnabled: true,
  );
  final deployment = localDevelopment
      ? AuthDeploymentPresets.localDevelopment<EngineContext>(
          providers: authProviders,
          plugins: [apiKeys],
          trustedOrigins: [origin],
          rateLimiter: RoutedAuthRateLimiter(configuredRateLimitService),
        )
      : AuthDeploymentPresets.secureSessionProduction<EngineContext>(
          store: store,
          providers: authProviders,
          plugins: [apiKeys],
          boundary: AuthProductionBoundary(
            trustedOrigins: [origin],
            proxyPolicy: const AuthProxyPolicy.direct(),
          ),
          lifecycleDelivery: const AuthLifecycleDelivery.disabled(),
          rateLimiter: RoutedAuthRateLimiter(configuredRateLimitService),
          requireVerifiedEmail: false,
          // This example does not configure an email delivery provider. Add
          // one and switch this to `AuthAccountPolicy.production` before
          // using email verification as an account activation requirement.
          accountPolicy: const AuthAccountPolicy(
            requireEmailVerification: false,
            allowUnverifiedSignIn: true,
          ),
          frameworkSessionHooks: AuthFrameworkSessionHooks<EngineContext>(
            afterSignOut: (context) {
              final session = context.session;
              context.response.setCookie(
                session.name,
                '',
                maxAge: 0,
                path: session.options.path ?? '/',
                domain: session.options.domain ?? '',
                secure: session.options.secure ?? false,
                httpOnly: session.options.httpOnly ?? true,
                sameSite: session.options.sameSite,
              );
            },
          ),
        );

  return AppConfig(
    engineConfig: deployment.engineConfig(),
    options: [deployment.bindTo],
    providers: [
      ...Engine.defaultProviders,
      RoutedSessionsProvider(
        SessionConfig.cookie(
          appKey: sessionKey,
          options: SessionOptions(
            path: '/',
            secure: !localDevelopment,
            httpOnly: true,
            sameSite: SameSite.lax,
          ),
        ),
      ),
      RoutedRateLimitProvider(
        RateLimitConfig(service: configuredRateLimitService),
      ),
      EmbeddedViewsProvider(),
      deployment.serviceProvider(),
    ],
  );
}

/// Creates the application's built-in rate-limit service.
///
/// A host can supply a durable [Repository] here. The Cloudflare Worker uses
/// the SQLite-backed Durable Object store, while the default remains useful
/// for local and test composition.
RateLimitService createRateLimitService({Repository? repository}) {
  final backend = CacheRateLimiterBackend(
    repository:
        repository ??
        RepositoryImpl(ArrayStore(), 'routed-auth-rate-limit', ''),
  );
  return RateLimitService(
    compileRateLimitPolicies(
      specs: const [
        RateLimitPolicySpec(
          name: 'auth-ip',
          match: '/auth/**',
          method: null,
          strategy: RateLimitStrategy.slidingWindow,
          capacity: 30,
          interval: Duration.zero,
          window: Duration(minutes: 1),
          period: Duration.zero,
          burstMultiplier: null,
          key: RateLimitKeySpec.ip(),
        ),
      ],
      backend: backend,
      defaultFailover: RateLimitFailoverMode.block,
    ),
  );
}
