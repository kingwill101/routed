library;

import '../property_context.dart';
import 'inertia_prop.dart';
import 'prop_mixins.dart';

/// Defines a prop excluded on the first load that resolves on partial reloads.
///
/// ```dart
/// final props = {
///   'stats': OptionalProp(() => expensiveStats()),
/// };
/// ```
class OptionalProp<T> with ResolvesOnce implements InertiaProp, OnceableProp {
  /// Creates an optional prop backed by [resolver].
  ///
  /// If [once], [ttl], [onceKey], or [refresh] is provided, the prop is
  /// configured to resolve once.
  OptionalProp(
    this.resolver, {
    bool once = false,
    Duration? ttl,
    String? onceKey,
    bool refresh = false,
  }) {
    if (once || ttl != null || onceKey != null || refresh) {
      configureOnce(once: true, ttl: ttl, key: onceKey, refresh: refresh);
    }
  }

  /// The resolver that produces the prop value.
  final T Function() resolver;
  T? _resolvedValue;

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
  T resolve(String key, PropertyContext context) {
    // Return cached value if already resolved
    if (_resolvedValue != null) return _resolvedValue!;

    // Only resolve on partial reloads if requested
    if (!shouldInclude(key, context)) {
      throw Exception('Optional property accessed without being requested');
    }

    _resolvedValue = resolver();
    return _resolvedValue!;
  }

  /// Marks this prop to resolve once, optionally keyed and time-limited.
  OptionalProp<T> once({String? key, Duration? ttl}) {
    configureOnce(once: true, key: key, ttl: ttl);
    return this;
  }

  /// Enables or disables refresh behavior for once props.
  OptionalProp<T> fresh([bool value = true]) {
    refresh(value);
    return this;
  }

  /// Sets a stable once key for this prop.
  OptionalProp<T> withKey(String key) {
    as(key);
    return this;
  }
}
