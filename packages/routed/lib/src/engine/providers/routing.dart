import 'package:routed/src/config/specs/routing.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/events/signals.dart';
import 'package:routed/src/validation/validator.dart';

import '../../container/container.dart' show Container;
import '../../engine/engine.dart';
import '../../provider/provider.dart';

/// A service provider that registers routing and event-related services.
///
/// This provider is responsible for:
/// - Registering the event manager
/// - Setting up routing event listeners
/// - Configuring routing-related services
///
/// Example:
/// ```dart
/// final engine = Engine();
/// engine.registerProvider(RoutingServiceProvider());
/// ```
class RoutingServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  Engine? _engine;
  static const RoutingConfigSpec spec = RoutingConfigSpec();

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: spec.docs(),
    values: spec.defaultsWithRoot(),
    schemas: spec.schemaWithRoot(),
  );

  @override
  void register(Container container) {
    if (!container.has<RoutePatternRegistry>()) {
      container.instance<RoutePatternRegistry>(RoutePatternRegistry.defaults());
    }
    if (!container.has<ValidationRuleRegistry>()) {
      container.instance<ValidationRuleRegistry>(
        ValidationRuleRegistry.defaults(),
      );
    }
    // Register event manager as a singleton
    container.singleton<EventManager>((c) async => EventManager());
  }

  @override
  Future<void> boot(Container container) async {
    Engine? engine;
    if (container.has<Engine>()) {
      engine = await container.make<Engine>();
      if (container.has<Config>()) {
        _applyRoutingConfig(engine, container.get<Config>());
      }
    }
    _engine = engine;

    final eventManager = await container.make<EventManager>();

    if (!container.has<SignalHub>()) {
      container.instance<SignalHub>(SignalHub(eventManager));
    }

    // Set up routing event listeners
    eventManager.listen((BeforeRoutingEvent event) {});

    eventManager.listen((RouteMatchedEvent event) {});

    eventManager.listen((RouteNotFoundEvent event) {});

    eventManager.listen((RoutingErrorEvent event) {});

    eventManager.listen((AfterRoutingEvent event) {});

    eventManager.listen<RouteCacheInvalidatedEvent>((_) {
      _engine?.invalidateRoutes();
    });
  }

  @override
  Future<void> cleanup(Container container) async {
    final engine = _engine;
    final isRootContainer =
        engine != null && identical(container, engine.container);
    if (!isRootContainer) {
      return;
    }

    if (!container.has<EventManager>()) {
      return;
    }

    final eventManager = await container.make<EventManager>();
    eventManager.destroy();

    if (container.has<SignalHub>()) {
      final hub = container.get<SignalHub>();
      hub.dispose();
      container.remove<SignalHub>();
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final engine =
        _engine ??
        (container.has<Engine>() ? await container.make<Engine>() : null);
    if (engine != null) {
      _applyRoutingConfig(engine, config);
    }
  }

  void _applyRoutingConfig(Engine engine, Config config) {
    final current = engine.config;
    final resolved = spec.resolve(
      config,
      context: RoutingConfigContext(config: config, engineConfig: current),
    );

    if (resolved.redirectTrailingSlash != current.redirectTrailingSlash ||
        resolved.handleMethodNotAllowed != current.handleMethodNotAllowed ||
        resolved.defaultOptionsEnabled != current.defaultOptionsEnabled ||
        resolved.etagStrategy != current.etagStrategy) {
      engine.updateConfig(
        current.copyWith(
          redirectTrailingSlash: resolved.redirectTrailingSlash,
          handleMethodNotAllowed: resolved.handleMethodNotAllowed,
          defaultOptionsEnabled: resolved.defaultOptionsEnabled,
          etagStrategy: resolved.etagStrategy,
        ),
      );
    }
  }
}
