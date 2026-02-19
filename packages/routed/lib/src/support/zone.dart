import 'dart:async';

import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/events/signals.dart';

// Helper to get zone values with better error messages
T zoneValue<T>(Symbol key, String name) {
  final value = Zone.current[key];
  if (value == null) {
    throw StateError(
      '$name not found in current zone. Are you running inside an AppZone?',
    );
  }
  return value as T;
}

class AppZone {
  static const _configKey = #config;
  static const _engineKey = #engine;
  static const _contextKey = #context;
  static const _signalsKey = #signals;

  // Access the current zone's values
  static Config get config {
    final engine = zoneValue<Engine>(_engineKey, 'Engine');
    final EngineContext? context = Zone.current[_contextKey] as EngineContext?;

    if (context != null) {
      try {
        return context.container.get<Config>();
      } catch (_) {
        // Fall through to engine-level lookup if context container lacks Config.
      }
    }

    try {
      return engine.container.get<Config>();
    } catch (_) {
      return zoneValue<Config>(_configKey, 'Config');
    }
  }

  static Engine get engine => zoneValue<Engine>(_engineKey, 'Engine');

  static EngineContext get context =>
      zoneValue<EngineContext>(_contextKey, 'EngineContext');

  static SignalHub get signals {
    final current = Zone.current[_signalsKey];
    if (current is SignalHub) return current;

    final engine = zoneValue<Engine>(_engineKey, 'Engine');
    final EngineContext? ctx = Zone.current[_contextKey] as EngineContext?;
    final hub = _resolveSignalHub(engine: engine, context: ctx);
    if (hub == null) {
      throw StateError(
        'SignalHub not found in current zone. Ensure EventManager is registered.',
      );
    }
    return hub;
  }

  // Helper to get the engine config
  static EngineConfig get engineConfig => engine.config;

  // Helper for route generation
  static String route(String name, [Map<String, dynamic>? parameters]) {
    final path = engine.route(name, parameters);
    if (path == null) {
      throw StateError('Route "$name" not found in current zone');
    }
    return path;
  }

  // Run code with zone values
  static FutureOr<R> run<R>({
    required FutureOr<R> Function() body,
    required Engine engine,
    EngineContext? context,
    Config? configOverride,
  }) async {
    final zoneConfig = _resolveConfigForZone(
      engine: engine,
      context: context,
      override: configOverride,
    );

    // Propagate errors to the caller so test failures and exceptions are not swallowed.
    final signalHub = _resolveSignalHub(engine: engine, context: context);

    return await runZoned(
      () async => await body(),
      zoneValues: {
        _engineKey: engine,
        _configKey: zoneConfig,
        _contextKey: context,
        _signalsKey: ?signalHub,
      },
      zoneSpecification: const ZoneSpecification(),
    );
  }

  static FutureOr<R> runWithConfig<R>({
    required Config config,
    required FutureOr<R> Function() body,
  }) async {
    final engine = AppZone.engine;
    final EngineContext? context = Zone.current[_contextKey] as EngineContext?;
    final container = context != null ? context.container : engine.container;

    Config? previous;
    if (container.has<Config>()) {
      try {
        previous = container.get<Config>();
      } catch (_) {
        previous = null;
      }
    }

    container.instance<Config>(config);

    try {
      return await run<R>(
        body: body,
        engine: engine,
        context: context,
        configOverride: config,
      );
    } finally {
      if (previous != null) {
        container.instance<Config>(previous);
      }
    }
  }

  static Config _resolveConfigForZone({
    required Engine engine,
    EngineContext? context,
    Config? override,
  }) {
    if (override != null) {
      return override;
    }

    if (context != null) {
      try {
        return context.container.get<Config>();
      } catch (_) {
        // Fall back to engine config when request container is missing binding.
      }
    }

    return engine.appConfig;
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
