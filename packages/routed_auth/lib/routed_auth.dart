/// Routed authentication middleware, guards, providers, and session helpers.
///
/// This library re-exports the framework-agnostic APIs from `server_auth` and
/// adapts them to `EngineContext` request and response lifecycles.
library;

import 'package:routed_auth/src/auth/provider.dart' show AuthServiceProvider;
import 'package:routed_core/routed_core.dart' show ProviderRegistry;

export 'package:server_auth/server_auth.dart';
export 'src/auth/manager/auth_manager.dart';
export 'src/auth/api_key.dart';
export 'src/auth/browser_protection.dart';
export 'src/auth/deployment.dart';
export 'src/auth/hooks.dart';
export 'src/auth/routes.dart';
export 'src/auth/haigate.dart'
    show
        GatePayloadProvider,
        GateDeniedHandler,
        GateViolation,
        registerPoliciesWithHaigate,
        gateRegistry,
        Haigate;
export 'src/auth/jwt.dart' show jwtAuthentication;
export 'src/auth/last_authentication_method.dart'
    show RoutedAuthLastAuthenticationMethodBrowserStore;
export 'src/auth/provider.dart' show AuthServiceProvider;
export 'src/auth/oauth.dart' show oauth2Introspection;
export 'src/auth/session_auth.dart'
    show
        SessionAuthService,
        SessionAuth,
        guardRegistry,
        guardMiddleware,
        requireAuthenticated,
        requireRoles;
export 'src/crypto/crypto.dart'
    show
        sha1Digest,
        sha256Digest,
        md5Digest,
        hmacSha256,
        constantTimeEqualsBytes,
        hexFromBytes;

/// Ensures the Routed auth provider ID is available in [registry].
///
/// Uses [ProviderRegistry.instance] when [registry] is omitted; a supplied
/// registry is updated independently of the global registry.
void ensureRoutedAuthProviderRegistered([ProviderRegistry? registry]) {
  final target = registry ?? ProviderRegistry.instance;
  if (!target.has('routed.auth')) {
    target.register(
      'routed.auth',
      factory: () => AuthServiceProvider(),
      description: 'Authentication helpers (JWT middleware, validators).',
    );
  }
}

/// Alias for [ensureRoutedAuthProviderRegistered].
void registerRoutedAuthProviders([ProviderRegistry? registry]) =>
    ensureRoutedAuthProviderRegistered(registry);
