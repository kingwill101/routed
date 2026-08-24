/// Defines a mutable, string-keyed configuration tree.
///
/// Keys are dot-notated paths, such as `database.host`, so implementations
/// can expose nested configuration without requiring callers to know the
/// underlying map representation. Typed reads should preserve the distinction
/// between a missing key and a configured value of the wrong type.
abstract class Config {
  /// Whether a value is configured at [key].
  ///
  /// A configured value may be `null`; implementations should use key
  /// existence, rather than a null value, to determine the result.
  bool has(String key);

  /// Returns the typed value at [key], or [defaultValue] when [key] is absent.
  ///
  /// Implementations should throw when a value is present but is not
  /// assignable to [T]. A `null` [defaultValue] is therefore used for a
  /// missing key, not as a request to ignore a type mismatch.
  T? get<T>(String key, [T? defaultValue]);

  /// Returns the typed value at [key], or throws when it cannot be read.
  ///
  /// The optional [message] customizes the error for a missing key. A value
  /// with an incompatible runtime type is also an error, even when [message]
  /// is supplied.
  T getOrThrow<T>(String key, {String? message});

  /// Returns the complete current configuration tree.
  ///
  /// The returned map uses the same nested representation addressed by
  /// dot-notated keys. Callers should treat it as a view or snapshot according
  /// to the implementation's ownership rules rather than relying on a
  /// particular mutability policy.
  Map<String, dynamic> all();

  /// Replaces the value at [key] with [value].
  ///
  /// Intermediate maps are created as needed for a dot-notated key.
  void set(String key, dynamic value);

  /// Inserts [value] at the beginning of the list at [key].
  ///
  /// If [key] does not contain a list, the implementation creates the list
  /// before inserting the value.
  void prepend(String key, dynamic value);

  /// Appends [value] to the end of the list at [key].
  ///
  /// If [key] does not contain a list, the implementation creates the list
  /// before appending the value.
  void push(String key, dynamic value);

  /// Deep-merges [values] into the current configuration.
  ///
  /// Nested maps are merged recursively and incoming scalar or list values
  /// replace the values at the corresponding paths.
  void merge(Map<String, dynamic> values);

  /// Deep-merges [values] only into paths that are not configured.
  ///
  /// Existing scalar, list, and map values are preserved. Missing entries
  /// inside an existing map are still added recursively.
  void mergeDefaults(Map<String, dynamic> values);
}
