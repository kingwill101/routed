import 'zone.dart';

T config<T>(String key, [T? defaultValue]) {
  return AppZone.config.get(key, defaultValue);
}

// Engine get engine => AppZone.engine;
//
// EngineConfig get engineConfig => AppZone.engineConfig;

String route(String name, [Map<String, dynamic>? parameters]) {
  return AppZone.route(name, parameters);
}
