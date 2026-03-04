library;

import 'package:routed/providers.dart' show ProviderRegistry;
import 'package:routed_auth/src/auth/provider.dart' show AuthServiceProvider;

export 'src/auth/manager/auth_manager.dart';
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
export 'src/config/specs/auth.dart' show AuthConfigSpec;

/// Ensures the Routed auth provider ID is available in the global registry.
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
