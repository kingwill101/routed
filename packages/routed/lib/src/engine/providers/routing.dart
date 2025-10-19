import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/events/event_manager.dart';

import '../../container/container.dart' show Container;
import '../../engine/config.dart' show EtagStrategy;
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

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: [
      ConfigDocEntry(
        path: 'routing.redirect_trailing_slash',
        type: 'bool',
        description: 'Automatically redirect /path/ to /path.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'routing.handle_method_not_allowed',
        type: 'bool',
        description:
            'Return 405 responses when a route exists but the method does not.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'routing.default_options',
        type: 'bool',
        description:
            'Serve automatic OPTIONS responses enumerating allowed methods when no handler is defined.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'routing.etag.strategy',
        type: 'string',
        description:
            'Default ETag strategy used by conditional request helpers (disabled, strong, weak).',
        defaultValue: 'disabled',
      ),
    ],
  );

  @override
  void register(Container container) {
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

    // Set up routing event listeners
    eventManager.listen((BeforeRoutingEvent event) {});

    eventManager.listen((RouteMatchedEvent event) {});

    eventManager.listen((RouteNotFoundEvent event) {});

    eventManager.listen((RoutingErrorEvent event) {});

    eventManager.listen((AfterRoutingEvent event) {});
  }

  @override
  Future<void> cleanup(Container container) async {
    if (container.has<EventManager>()) {
      final eventManager = await container.make<EventManager>();
      eventManager.destroy();
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
    final redirectTrailingSlash = _resolveFlag(
      config.get('routing.redirect_trailing_slash'),
      fallback: current.redirectTrailingSlash,
    );
    final handleMethodNotAllowed = _resolveFlag(
      config.get('routing.handle_method_not_allowed'),
      fallback: current.handleMethodNotAllowed,
    );
    final defaultOptionsEnabled = _resolveFlag(
      config.get('routing.default_options'),
      fallback: current.defaultOptionsEnabled,
    );
    final etagStrategy = _parseEtagStrategy(
      config.get('routing.etag.strategy'),
      current.etagStrategy,
    );

    if (redirectTrailingSlash != current.redirectTrailingSlash ||
        handleMethodNotAllowed != current.handleMethodNotAllowed ||
        defaultOptionsEnabled != current.defaultOptionsEnabled ||
        etagStrategy != current.etagStrategy) {
      engine.updateConfig(
        current.copyWith(
          redirectTrailingSlash: redirectTrailingSlash,
          handleMethodNotAllowed: handleMethodNotAllowed,
          defaultOptionsEnabled: defaultOptionsEnabled,
          etagStrategy: etagStrategy,
        ),
      );
    }
  }

  bool _resolveFlag(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return fallback;
  }

  EtagStrategy _parseEtagStrategy(Object? value, EtagStrategy fallback) {
    if (value is EtagStrategy) {
      return value;
    }
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'disabled':
        case 'none':
          return EtagStrategy.disabled;
        case 'weak':
          return EtagStrategy.weak;
        case 'strong':
          return EtagStrategy.strong;
      }
    }
    return fallback;
  }
}
