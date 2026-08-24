import 'package:routed_auth/src/auth/provider.dart';
import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart';

/// Routed-specific binding helpers for a typed [AuthDeployment].
extension RoutedAuthDeploymentBinding on AuthDeployment<EngineContext> {
  /// Creates the auth provider configured by this deployment.
  ///
  /// Pair the result with this deployment's `bindTo` call before engine
  /// initialization so boot can verify the exact options identity.
  AuthServiceProvider serviceProvider() => createDeploymentAuthServiceProvider(
    configuration: configuration,
    options: options,
  );

  /// Binds the deployment's runtime options before [Engine.initialize].
  ///
  /// Installs this exact [AuthOptions] identity in the engine container.
  /// Omitting this call or binding options from another deployment causes the
  /// deployment-created provider to fail during boot.
  void bindTo(Engine engine) {
    engine.container.instance<AuthOptions<EngineContext>>(options);
  }

  /// Applies the deployment's explicit proxy decision to Routed's engine.
  ///
  /// Existing unrelated engine settings are retained. A direct policy disables
  /// forwarded-header processing; a trusted policy enables it only for the
  /// configured proxy networks and header names. The optional [base] config is
  /// copied so unrelated engine settings remain unchanged.
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
