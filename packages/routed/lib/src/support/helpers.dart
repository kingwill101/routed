import 'zone.dart';

T config<T>(String key, [T? defaultValue]) {
  final value = AppZone.config.get(key, defaultValue);
  return value is T ? value : defaultValue as T;
}

// Engine get engine => AppZone.engine;
//
// EngineConfig get engineConfig => AppZone.engineConfig;

String route(String name, [Map<String, dynamic>? parameters]) {
  return AppZone.route(name, parameters);
}
