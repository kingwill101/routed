/// Typed key for [RouteMetadata] entries.
///
/// The router stores metadata but does not interpret feature-specific values.
/// Each feature defines its own key, e.g.:
/// ```dart
/// const openApiOperationKey = RouteMetadataKey<OpenApiOperation>('routed.openapi.operation');
/// ```
final class RouteMetadataKey<T> {
  /// Creates a [RouteMetadataKey].
  const RouteMetadataKey(this.name);

  /// Namespaced key name, e.g. 'routed.auth.policy'.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is RouteMetadataKey<T> && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'RouteMetadataKey<$T>($name)';
}

/// Generic typed metadata bag attached to a route.
///
/// Stored by the router, interpreted by feature packages.
class RouteMetadata {
  final Map<String, Object?> _values = {};

  /// Reads value for [key] or `null` if absent or type mismatch.
  T? get<T>(RouteMetadataKey<T> key) {
    final value = _values[key.name];
    if (value is T) return value;
    return null;
  }

  /// Writes [value] for [key]. Overwrites any previous entry.
  void set<T>(RouteMetadataKey<T> key, T value) {
    _values[key.name] = value;
  }

  /// Returns `true` if [key] is present.
  bool contains<T>(RouteMetadataKey<T> key) => _values.containsKey(key.name);

  /// Removes entry for [key].
  void remove<T>(RouteMetadataKey<T> key) => _values.remove(key.name);

  /// Unmodifiable view for debugging/inspection.
  Map<String, Object?> get asMap => Map.unmodifiable(_values);
}
