import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart';

import 'provider.dart';

/// Routed-specific binding helpers for a typed [AuthDeployment].
extension RoutedAuthDeploymentBinding<TContext> on AuthDeployment<TContext> {
  /// Creates the auth provider configured by this deployment.
  AuthServiceProvider serviceProvider() => AuthServiceProvider(
    configuration: configuration,
    requireDurableStore: requiresDurableStore,
  );

  /// Binds the deployment's runtime options before [Engine.initialize].
  void bindTo(Engine engine) {
    engine.container.instance<AuthOptions<TContext>>(options);
  }

  /// Applies the deployment's explicit proxy decision to Routed's engine.
  ///
  /// Existing unrelated engine settings are retained. A direct policy disables
  /// forwarded-header processing; a trusted policy enables it only for the
  /// configured proxy networks and header names.
  EngineConfig engineConfig([EngineConfig? base]) {
    final source = base ?? EngineConfig();
    final policy = proxyPolicy;
    final features = source.features;
    return source.copyWith(
      features: EngineFeatures(
        enableTrustedPlatform:
            policy.trustsForwardedHeaders && policy.platformHeader != null,
        enableProxySupport: policy.trustsForwardedHeaders,
        enableSecurityFeatures: features.enableSecurityFeatures,
        enableRequestZones: features.enableRequestZones,
        enableRequestContainerFastPath: features.enableRequestContainerFastPath,
        enableTrieRouting: features.enableTrieRouting,
        enableSecureRequestIds: features.enableSecureRequestIds,
      ),
      forwardedByClientIP:
          policy.trustsForwardedHeaders && policy.forwardClientIp,
      remoteIPHeaders: policy.headers,
      trustedProxies: policy.proxies,
      trustedPlatform: policy.platformHeader,
    );
  }
}
