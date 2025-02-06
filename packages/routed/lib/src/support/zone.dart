import 'dart:async';

import 'package:routed/src/contracts/config.dart/config.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';

class AppZone {
  static const _configKey = #config;
  static const _engineKey = #engine;

  // Access the current zone's values
  static Config get config => _get<Config>(_configKey, 'Config');
  static Engine get engine => _get<Engine>(_engineKey, 'Engine');

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

  // Helper to get zone values with better error messages
  static T _get<T>(Symbol key, String name) {
    final value = Zone.current[key];
    if (value == null) {
      throw StateError(
          '$name not found in current zone. Are you running inside an AppZone?');
    }
    return value as T;
  }

  // Run code with zone values
  static Future<R> run<R>({
    required FutureOr<R> Function() body,
    required Engine engine,
  }) async {
    return await runZoned(
      () async => await body(),
      zoneValues: {
        _engineKey: engine,
        _configKey: engine.appConfig,
      },
    );
  }
}
