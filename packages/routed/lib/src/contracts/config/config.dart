import 'dart:async';

import 'package:routed/src/config/runtime.dart' as config_runtime;

abstract class Config {
  /// Retrieves the configuration associated with the current AppZone.
  static Config get current => config_runtime.currentConfig();

  /// Runs [body] with the given [config] bound for the lifetime of that call.
  ///
  /// The provided configuration becomes accessible via [Config.current] and
  /// container resolution within the current zone until the callback completes.
  static FutureOr<T> runWith<T>(Config config, FutureOr<T> Function() body) {
    return config_runtime.runWithConfig(config, body);
  }

  /// Determines if the given configuration value exists.
  ///
  /// Returns `true` if the configuration value exists, otherwise `false`.
  bool has(String key);

  /// Gets the specified configuration value.
  ///
  /// Returns the value associated with [key], or [defaultValue] if the key does not exist.
  T? get<T>(String key, [T? defaultValue]);

  /// Gets the specified configuration value, throwing if the key does not exist.
  T getOrThrow<T>(String key, {String? message});

  /// Gets all of the configuration items for the application.
  ///
  /// Returns a map of all configuration items.
  Map<String, dynamic> all();

  /// Sets a given configuration value.
  ///
  /// Sets the value for the specified [key] to [value].
  void set(String key, dynamic value);

  /// Prepends a value onto an array configuration value.
  ///
  /// Adds [value] to the beginning of the array associated with [key].
  void prepend(String key, dynamic value);

  /// Pushes a value onto an array configuration value.
  ///
  /// Adds [value] to the end of the array associated with [key].
  void push(String key, dynamic value);

  /// Deep-merges the provided [values] into the configuration.
  ///
  /// Map values are merged recursively, while non-map values replace existing entries.
  void merge(Map<String, dynamic> values);

  /// Merges [values] into the configuration only when keys are missing.
  void mergeDefaults(Map<String, dynamic> values);
}
