/// Stores shared props applied to every Inertia response.
///
/// ```dart
/// final shared = InertiaSharedProps()
///   ..set('appName', 'Inertia')
///   ..addAll({'featureFlags': {'beta': true}});
/// ```
class InertiaSharedProps {
  final Map<String, dynamic> _props = {};

  /// Whether there are no shared props.
  bool get isEmpty => _props.isEmpty;

  /// Returns an immutable snapshot of all shared props.
  Map<String, dynamic> all() => Map.unmodifiable(_props);

  /// Adds [props] to the shared prop set.
  void addAll(Map<String, dynamic> props) {
    _props.addAll(props);
  }

  /// Sets a single shared prop by [key].
  void set(String key, dynamic value) {
    _props[key] = value;
  }
}
