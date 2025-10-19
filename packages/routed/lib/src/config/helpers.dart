import 'dart:async';

import 'package:routed/src/contracts/contracts.dart';

/// Retrieves a configuration value using dot notation (e.g. `app.name`).
T? configValue<T>(String key, [T? defaultValue]) {
  final value = Config.current.get(key, defaultValue);
  return value == null ? defaultValue : value as T?;
}

/// Retrieves a configuration value or throws if the key is missing.
T configValueOrThrow<T>(String key, {String? message}) {
  return Config.current.getOrThrow<T>(key, message: message);
}

/// Runs [body] with the provided configuration bound for the duration of the call.
FutureOr<R> withConfig<R>(Config config, FutureOr<R> Function() body) {
  return Config.runWith(config, body);
}

/// Returns the entire configuration map or a namespaced view when [namespace] is provided.
Map<String, dynamic> configNamespace(String? namespace) {
  if (namespace == null || namespace.isEmpty) {
    return Config.current.all();
  }
  final value = Config.current.get(namespace);
  if (value is Map<String, dynamic>) {
    return value;
  }
  return <String, dynamic>{};
}
