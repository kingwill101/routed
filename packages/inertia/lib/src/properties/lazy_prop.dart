library;

import 'dart:async';

import '../property_context.dart';
import 'inertia_prop.dart';

/// Defines a prop that resolves only on partial reloads.
///
/// ```dart
/// final props = {
///   'stats': LazyProp(() => loadStats()),
/// };
/// ```
class LazyProp<T> implements InertiaProp {
  /// Creates a lazy prop backed by [resolver].
  LazyProp(this.resolver);

  /// The resolver that produces the prop value.
  final FutureOr<T> Function() resolver;
  FutureOr<T>? _cachedValue;

  @override
  /// Whether this prop should be included for the current [context].
  bool shouldInclude(String key, PropertyContext context) {
    if (!context.isPartialReload) return false;
    return context.shouldIncludeProp(key);
  }

  @override
  /// Resolves the prop when included; otherwise throws.
  ///
  /// #### Throws
  /// - [Exception] when the prop is accessed outside a requested partial reload.
  FutureOr<T> resolve(String key, PropertyContext context) {
    // Return cached value if already resolved
    final cached = _cachedValue;
    if (cached != null) return cached;

    if (shouldInclude(key, context)) {
      _cachedValue = resolver();
      return _cachedValue as FutureOr<T>;
    }

    throw Exception('Lazy property accessed without being requested');
  }
}
