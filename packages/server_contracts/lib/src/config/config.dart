/// Mutable configuration repository contract.
abstract class Config {
  /// Whether [key] exists.
  bool has(String key);

  /// Returns [key], or [defaultValue] when absent.
  T? get<T>(String key, [T? defaultValue]);

  /// Returns [key] or throws when no value is configured.
  T getOrThrow<T>(String key, {String? message});

  /// Returns a snapshot of all configuration values.
  Map<String, dynamic> all();

  /// Sets [value] for [key].
  void set(String key, dynamic value);

  /// Adds [value] to the beginning of the collection at [key].
  void prepend(String key, dynamic value);

  /// Adds [value] to the end of the collection at [key].
  void push(String key, dynamic value);

  /// Merges [values] into the current configuration.
  void merge(Map<String, dynamic> values);

  /// Merges [values] only where no value is already configured.
  void mergeDefaults(Map<String, dynamic> values);
}
