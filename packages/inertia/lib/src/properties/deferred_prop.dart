library;

import '../property_context.dart';
import 'inertia_prop.dart';
import 'prop_mixins.dart';

/// Defines a prop that resolves only when its deferred group is requested.
///
/// ```dart
/// final props = {
///   'feed': DeferredProp(() => loadFeed(), group: 'feed', merge: true),
/// };
/// ```
class DeferredProp<T>
    with DefersProps, MergesProps, ResolvesOnce
    implements InertiaProp, DeferrableProp, MergeableProp, OnceableProp {
  /// Creates a deferred prop backed by [resolver].
  ///
  /// Use [group] to name the deferred group. When [merge] or [deepMerge] is
  /// enabled, the client merges the resulting value into existing props.
  DeferredProp(
    this.resolver, {
    String group = 'default',
    bool merge = false,
    bool deepMerge = false,
    bool once = false,
    Duration? ttl,
    String? onceKey,
    bool refresh = false,
  }) {
    configureDeferred(deferred: true, group: group);
    if (merge) {
      configureMerge(true);
    }
    if (deepMerge) {
      configureDeepMerge(true);
    }
    if (once || ttl != null || onceKey != null || refresh) {
      configureOnce(once: true, ttl: ttl, key: onceKey, refresh: refresh);
    }
  }

  /// The resolver that produces the prop value.
  final T Function() resolver;

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
  /// - [Exception] when the prop is accessed outside a requested deferred load.
  T resolve(String key, PropertyContext context) {
    if (shouldInclude(key, context)) {
      return resolver();
    }

    throw Exception('Deferred property accessed without being requested');
  }

  @override
  /// Appends to a merge path and returns this prop for chaining.
  DeferredProp<T> append([Object? path, String? matchOn]) {
    super.append(path, matchOn);
    return this;
  }

  @override
  /// Prepends to a merge path and returns this prop for chaining.
  DeferredProp<T> prepend([Object? path, String? matchOn]) {
    super.prepend(path, matchOn);
    return this;
  }

  /// Adds a match-on key for merge semantics.
  DeferredProp<T> matchOn(Object? value) {
    configureMatchOn(value);
    return this;
  }

  /// Enables or disables deep merge behavior.
  DeferredProp<T> deepMerge([bool value = true]) {
    configureDeepMerge(value);
    return this;
  }

  /// Marks this prop to resolve once, optionally keyed and time-limited.
  DeferredProp<T> once({String? key, Duration? ttl}) {
    configureOnce(once: true, key: key, ttl: ttl);
    return this;
  }

  /// Enables or disables refresh behavior for once props.
  DeferredProp<T> fresh([bool value = true]) {
    refresh(value);
    return this;
  }

  /// Sets a stable once key for this prop.
  DeferredProp<T> withKey(String key) {
    as(key);
    return this;
  }
}
