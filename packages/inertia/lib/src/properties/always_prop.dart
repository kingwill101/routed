library;

import 'dart:async';

import '../property_context.dart';
import 'inertia_prop.dart';

/// Defines a prop that always resolves for every response.
///
/// ```dart
/// final props = {
///   'appName': AlwaysProp(() => 'Inertia'),
/// };
/// ```
class AlwaysProp<T> implements InertiaProp {
  /// Creates an always-included prop backed by [resolver].
  AlwaysProp(this.resolver);

  /// The resolver that produces the prop value.
  final FutureOr<T> Function() resolver;
  FutureOr<T>? _resolvedValue;

  @override
  /// Whether this prop should be included.
  bool shouldInclude(String key, PropertyContext context) => true;

  @override
  /// Resolves the prop and caches the value for reuse.
  FutureOr<T> resolve(String key, PropertyContext context) {
    // Return cached value if already resolved
    final resolved = _resolvedValue;
    if (resolved != null) return resolved;

    _resolvedValue = resolver();
    return _resolvedValue as FutureOr<T>;
  }
}
