library;

import 'dart:async';

import '../property_context.dart';
import 'inertia_prop.dart';
import 'prop_mixins.dart';

/// Defines a prop that resolves once and caches on the client.
///
/// ```dart
/// final props = {
///   'token': OnceProp(() => token, ttl: Duration(hours: 1)),
/// };
/// ```
class OnceProp<T> with ResolvesOnce implements InertiaProp, OnceableProp {
  /// Creates a once prop backed by [resolver].
  OnceProp(this.resolver, {Duration? ttl, String? key, bool refresh = false}) {
    configureOnce(once: true, ttl: ttl, key: key, refresh: refresh);
  }

  /// The resolver that produces the prop value.
  final FutureOr<T> Function() resolver;

  @override
  /// Whether this prop should be included for the current [context].
  bool shouldInclude(String key, PropertyContext context) {
    return context.shouldIncludeProp(key);
  }

  @override
  /// Resolves the prop value.
  FutureOr<T> resolve(String key, PropertyContext context) {
    return resolver();
  }

  /// Marks this prop to resolve once, optionally keyed and time-limited.
  OnceProp<T> once({String? key, Duration? ttl}) {
    configureOnce(once: true, key: key, ttl: ttl);
    return this;
  }

  /// Enables or disables refresh behavior for once props.
  OnceProp<T> fresh([bool value = true]) {
    refresh(value);
    return this;
  }

  /// Sets a stable once key for this prop.
  OnceProp<T> withKey(String key) {
    as(key);
    return this;
  }
}
