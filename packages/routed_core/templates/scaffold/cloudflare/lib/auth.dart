import 'package:routed_auth/routed_auth.dart';
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_auth/server_auth.dart';

/// The auth setup assembled from the Worker environment.
final class CloudflareAuthSetup {
  /// Creates a Cloudflare auth setup.
  const CloudflareAuthSetup({
    required this.deployment,
    required this.sessions,
  });

  /// Typed server-auth deployment used by Routed's auth provider.
  final AuthDeployment<EngineContext> deployment;

  /// Signed, HttpOnly cookie session configuration.
  final SessionConfig sessions;
}

/// Builds the D1-backed auth deployment for the Worker.
///
/// `AUTH_ORIGIN` must be the public HTTPS origin used by browser clients and
/// `SESSION_KEY` must be a long-lived secret binding. The auth schema is
/// namespaced so it can share the generated app D1 database safely.
Future<CloudflareAuthSetup> createCloudflareAuthSetup(
  CloudflareEnvironment environment, {
  bool includeUsername = false,
}) async {
  final origin = Uri.parse(cloudflareTextBinding(environment, 'AUTH_ORIGIN'));
  final sessionKey = cloudflareTextBinding(environment, 'SESSION_KEY');
  final store = await CloudflareD1AuthStore.open(
    environment.d1('DB'),
    schema: const CloudflareD1AuthSchema(tablePrefix: 'routed_auth'),
  );
  final deployment =
      AuthDeploymentPresets.secureSessionProduction<EngineContext>(
        store: store,
        providers: [
          CredentialsProvider(),
        ],
        plugins: [
          if (includeUsername) UsernamePlugin<EngineContext>(),
        ],
        boundary: AuthProductionBoundary(
          trustedOrigins: [origin],
          proxyPolicy: const AuthProxyPolicy.direct(),
        ),
        lifecycleDelivery: const AuthLifecycleDelivery.disabled(),
        rateLimiter: const AllowAllAuthRateLimiter(),
        requireVerifiedEmail: false,
        accountPolicy: const AuthAccountPolicy(
          requireEmailVerification: false,
          allowUnverifiedSignIn: true,
        ),
      );

  return CloudflareAuthSetup(
    deployment: deployment,
    sessions: SessionConfig.cookie(appKey: sessionKey),
  );
}

/// Explicit starter rate limiting policy.
///
/// The production auth preset requires an application-owned limiter. This
/// permissive implementation keeps the scaffold deployable without choosing
/// a Durable Object topology for every application. Replace it with a durable
/// `AuthRateLimiter<EngineContext>` before exposing authentication publicly.
final class AllowAllAuthRateLimiter implements AuthRateLimiter<EngineContext> {
  /// Creates the starter limiter.
  const AllowAllAuthRateLimiter();

  @override
  Future<AuthRateLimitDecision> check(
    AuthRateLimitRequest<EngineContext> _,
  ) async => const AuthRateLimitDecision.allow();
}
