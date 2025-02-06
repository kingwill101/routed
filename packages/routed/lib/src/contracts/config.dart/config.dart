abstract class Config {
  /// Determines if the given configuration value exists.
  ///
  /// Returns `true` if the configuration value exists, otherwise `false`.
  bool has(String key);

  /// Gets the specified configuration value.
  ///
  /// Returns the value associated with [key], or [defaultValue] if the key does not exist.
  dynamic get(String key, [dynamic defaultValue]);

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
}
