import 'dart:async';

import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/engine/config.dart';
import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/events/event_manager.dart';
import 'package:routed_core/src/events/signals.dart';

// Helper to get zone values with better error messages
/// Returns the value stored under [key] in the current application zone.
T zoneValue<T>(Symbol key, String name) {
  final value = Zone.current[key];
  if (value == null) {
    throw StateError(
      '$name not found in current zone. Are you running inside an AppZone?',
    );
  }
  return value as T;
}

/// Provides request-scoped Routed state through a zone.
class AppZone {
  static const _configurationKey = #configuration;
  static const _engineKey = #engine;
  static const _contextKey = #context;
  static const _signalsKey = #signals;

  // Access the current zone's values
  /// The configuration value.
  static ConfigStore get configuration {
    final engine = zoneValue<Engine>(_engineKey, 'Engine');
    final context = Zone.current[_contextKey] as EngineContext?;

    if (context != null) {
      try {
        return context.container.get<ConfigStore>();
      } catch (_) {
        // Fall through to engine-level lookup if context lacks configuration.
      }
    }

    try {
      return engine.container.get<ConfigStore>();
    } catch (_) {
      return zoneValue<ConfigStore>(_configurationKey, 'configuration');
    }
  }

  /// Backwards-readable alias for the typed configuration store.
  static ConfigStore get config => configuration;

  /// The engine value.
  static Engine get engine => zoneValue<Engine>(_engineKey, 'Engine');

  /// The context value.
  static EngineContext get context =>
      zoneValue<EngineContext>(_contextKey, 'EngineContext');

  /// The signals value.
  static SignalHub get signals {
    final current = Zone.current[_signalsKey];
    if (current is SignalHub) return current;

    final engine = zoneValue<Engine>(_engineKey, 'Engine');
    final ctx = Zone.current[_contextKey] as EngineContext?;
    final hub = _resolveSignalHub(engine: engine, context: ctx);
    if (hub == null) {
      throw StateError(
        'SignalHub not found in current zone. Ensure EventManager is registered.',
      );
    }
    return hub;
  }

  // Helper to get the engine config
  /// The engine config value.
  static EngineConfig get engineConfig => engine.config;

  // Helper for route generation
  /// Creates a [AppZone].
  static String route(String name, [Map<String, dynamic>? parameters]) {
    final path = engine.route(name, parameters);
    if (path == null) {
      throw StateError('Route "$name" not found in current zone');
    }
    return path;
  }

  // Run code with zone values
  /// Runs [body] with the supplied engine and request-scoped values.
  static FutureOr<R> run<R>({
    required FutureOr<R> Function() body,
    required Engine engine,
    EngineContext? context,
  }) async {
    final configuration = _resolveConfiguration(
      engine: engine,
      context: context,
    );

    // Propagate errors to the caller so test failures and exceptions are not swallowed.
    final signalHub = _resolveSignalHub(engine: engine, context: context);

    return await runZoned(
      () async => await body(),
      zoneValues: {
        _engineKey: engine,
        _configurationKey: configuration,
        _contextKey: context,
        _signalsKey: ?signalHub,
      },
      zoneSpecification: const ZoneSpecification(),
    );
  }

  /// Runs [body] with an explicit typed [configuration] store.
  static FutureOr<R> runWithConfiguration<R>({
    required ConfigStore configuration,
    required FutureOr<R> Function() body,
  }) async {
    final engine = AppZone.engine;
    final context = Zone.current[_contextKey] as EngineContext?;
    return await runZoned(
      body,
      zoneValues: {
        _engineKey: engine,
        _configurationKey: configuration,
        _contextKey: context,
      },
      zoneSpecification: const ZoneSpecification(),
    );
  }

  static ConfigStore _resolveConfiguration({
    required Engine engine,
    EngineContext? context,
  }) {
    if (context != null) {
      try {
        return context.container.get<ConfigStore>();
      } catch (_) {
        // Fall back to engine configuration when request scope is unavailable.
      }
    }

    return engine.configStore;
  }

  static SignalHub? _resolveSignalHub({
    required Engine engine,
    EngineContext? context,
  }) {
    final container = engine.container;
    try {
      if (!container.has<SignalHub>()) {
        if (!container.has<EventManager>()) {
          return null;
        }
        final manager = container.get<EventManager>();
        container.instance<SignalHub>(SignalHub(manager));
      }
      return container.get<SignalHub>();
    } catch (_) {
      return null;
    }
  }
}
