import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/engine/config.dart';
import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/provider/typed_provider.dart';
import 'package:routed_core/src/security/trusted_proxy_resolver.dart';

/// Registers the engine's typed core configuration and host-independent
/// security services.
///
/// Configuration is supplied as Dart values at the application boundary:
///
/// ```dart
/// final engine = await Engine.create(
///   providers: [
///     CoreServiceProvider(
///       EngineConfig(
///         features: const EngineFeatures(enableSecurityFeatures: true),
///         security: const EngineSecurityFeatures(maxRequestSize: 10 << 20),
///       ),
///     ),
///     RoutingServiceProvider(),
///   ],
/// );
/// ```
///
/// Environment variables and deployment secrets belong in [RuntimeContext]
/// and are resolved before providers boot. This provider intentionally has no
/// file loader, config directory, reload watcher, or string-key override path.
class CoreServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<EngineConfig> {
  /// Creates a core provider with [configuration], or the safe framework
  /// defaults when no configuration is supplied.
  CoreServiceProvider([EngineConfig? configuration])
    : configuration = configuration ?? EngineConfig();

  @override
  final EngineConfig configuration;

  @override
  void register(Container container) {
    // Engine installs a default before providers register. Rebinding here
    // makes an explicitly supplied CoreServiceProvider authoritative.
    container.instance<EngineConfig>(configuration);
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Engine>()) {
      return;
    }

    final engine = await container.make<Engine>();
    final resolved = container.has<ConfigStore>()
        ? container.get<ConfigStore>().maybe<EngineConfig>() ?? configuration
        : configuration;

    engine.updateConfig(resolved);
    container.instance<TrustedProxyResolver>(
      TrustedProxyResolver(
        enabled: resolved.features.enableProxySupport,
        forwardClientIp: resolved.forwardedByClientIP,
        proxies: resolved.trustedProxies,
        headers: resolved.remoteIPHeaders,
        trustedPlatform: resolved.trustedPlatform,
      ),
    );
  }
}
