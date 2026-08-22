import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';
import 'package:routed_sessions/routed_sessions.dart';

const _authTablePrefix = 'routed_cloudflare_auth';

/// Creates the production Worker engine from Cloudflare's typed bindings.
Future<Engine> createCloudflareEngine(CloudflareEnvironment environment) async {
  final origin = Uri.parse(cloudflareTextBinding(environment, 'AUTH_ORIGIN'));
  final sessionKey = cloudflareTextBinding(environment, 'SESSION_KEY');
  final store = await CloudflareD1AuthStore.open(
    environment.d1('AUTH_DB'),
    schema: const CloudflareD1AuthSchema(tablePrefix: _authTablePrefix),
  );
  return buildAuthEngine(store: store, origin: origin, sessionKey: sessionKey);
}

/// Builds the HTTP application around any durable [AuthStore].
///
/// Keeping this composition separate makes the Worker easy to smoke-test on
/// Dart IO with [SqliteAuthStore], which implements the same D1 contract.
Future<Engine> buildAuthEngine({
  required AuthStore store,
  required Uri origin,
  required String sessionKey,
}) async {
  if (sessionKey.trim().isEmpty) {
    throw ArgumentError.value(
      sessionKey,
      'sessionKey',
      'must be provided through a secret binding',
    );
  }

  // The example keeps the rate-limit service explicitly wired, even though
  // this repository does not yet provide a durable Cloudflare rate-limit
  // backend. Add policies and a D1/KV-backed backend before exposing this
  // example to untrusted public traffic.
  final rateLimitService = RateLimitService(const []);
  final deployment =
      AuthDeploymentPresets.secureSessionProduction<EngineContext>(
        store: store,
        providers: [CredentialsProvider()],
        boundary: AuthProductionBoundary(
          trustedOrigins: [origin],
          proxyPolicy: const AuthProxyPolicy.direct(),
        ),
        lifecycleDelivery: const AuthLifecycleDelivery.disabled(),
        rateLimiter: RoutedAuthRateLimiter(rateLimitService),
        requireVerifiedEmail: false,
        // This example does not configure an email delivery provider. Add
        // one and switch this to `AuthAccountPolicy.production` before using
        // email verification as an account activation requirement.
        accountPolicy: const AuthAccountPolicy(
          requireEmailVerification: false,
          allowUnverifiedSignIn: true,
        ),
      );

  final engine = Engine(
    config: deployment.engineConfig(),
    providers: [
      ...Engine.defaultProviders,
      RoutedSessionsProvider(
        SessionConfig.cookie(
          appKey: sessionKey,
          options: SessionOptions(
            path: '/',
            secure: true,
            httpOnly: true,
            sameSite: SameSite.lax,
          ),
        ),
      ),
      RoutedRateLimitProvider(RateLimitConfig(service: rateLimitService)),
      deployment.serviceProvider(),
    ],
  );
  deployment.bindTo(engine);

  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

  engine.get('/', (context) {
    return context.json(<String, Object?>{
      'service': 'routed_cloudflare_auth_example',
      'routes': <String, String>{
        'health': '/health',
        'providers': '/auth/providers',
        'csrf': '/auth/csrf',
        'register': '/auth/register/credentials',
        'signIn': '/auth/signin/credentials',
        'account': '/account',
        'signOut': '/auth/signout',
      },
    });
  });

  engine.get('/health', (context) {
    return context.json(<String, Object?>{
      'ok': true,
      'store': 'cloudflare_d1',
      'sessions': 'encrypted_cookie',
    });
  });

  engine.get(
    '/account',
    (context) {
      final principal = SessionAuth.current(context);
      return context.json(<String, Object?>{
        'authenticated': true,
        'userId': principal?.id,
        'email': principal?.attributes['email'],
      });
    },
    middlewares: [
      guardMiddleware(['authenticated']),
    ],
  );

  await engine.initialize();
  return engine;
}
