import 'package:routed_core/src/config/specs/routing.dart';
import 'package:routed_core/src/container/container.dart' show Container;
import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/events/event_manager.dart';
import 'package:routed_core/src/events/signals.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/provider/typed_provider.dart';

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
    with ProvidesTypedConfiguration<RoutingConfig> {
  /// Creates a routing provider with optional [configuration].
  RoutingServiceProvider([RoutingConfig? configuration])
    : configuration = configuration ?? const RoutingConfig();

  @override
  final RoutingConfig configuration;

  Engine? _engine;

  @override
  void register(Container container) {
    if (!container.has<RoutePatternRegistry>()) {
      container.instance<RoutePatternRegistry>(RoutePatternRegistry.defaults());
    }
    // Register event manager as a singleton
    container.singleton<EventManager>((c) async => EventManager());
  }

  @override
  Future<void> boot(Container container) async {
    Engine? engine;
    if (container.has<Engine>()) {
      engine = await container.make<Engine>();
      _applyRoutingConfig(engine, configuration);
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

  void _applyRoutingConfig(Engine engine, RoutingConfig resolved) {
    final current = engine.config;

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
