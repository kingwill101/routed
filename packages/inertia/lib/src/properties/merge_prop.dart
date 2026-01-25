library;

import '../property_context.dart';
import 'inertia_prop.dart';
import 'prop_mixins.dart';

/// Defines a prop that merges into existing props on the client.
///
/// ```dart
/// final props = {
///   'items': MergeProp(() => fetchItems()).append('items', 'id'),
/// };
/// ```
class MergeProp<T>
    with MergesProps, ResolvesOnce
    implements InertiaProp, MergeableProp, OnceableProp {
  /// Creates a mergeable prop backed by [resolver].
  ///
  /// Use [deepMerge] to merge nested structures and [once] options to cache.
  MergeProp(
    this.resolver, {
    bool deepMerge = false,
    bool once = false,
    Duration? ttl,
    String? onceKey,
    bool refresh = false,
  }) {
    configureMerge(true);
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
    return context.shouldIncludeProp(key);
  }

  @override
  /// Resolves the prop when included; otherwise throws.
  ///
  /// #### Throws
  /// - [Exception] when the prop is accessed without being requested.
  T resolve(String key, PropertyContext context) {
    if (shouldInclude(key, context)) {
      return resolver();
    }

    throw Exception('Merge property accessed without being requested');
  }

  @override
  /// Appends to a merge path and returns this prop for chaining.
  MergeProp<T> append([Object? path, String? matchOn]) {
    super.append(path, matchOn);
    return this;
  }

  @override
  /// Prepends to a merge path and returns this prop for chaining.
  MergeProp<T> prepend([Object? path, String? matchOn]) {
    super.prepend(path, matchOn);
    return this;
  }

  /// Adds a match-on key for merge semantics.
  MergeProp<T> matchOn(Object? value) {
    configureMatchOn(value);
    return this;
  }

  /// Enables or disables deep merge behavior.
  MergeProp<T> deepMerge([bool value = true]) {
    configureDeepMerge(value);
    return this;
  }

  /// Marks this prop to resolve once, optionally keyed and time-limited.
  MergeProp<T> once({String? key, Duration? ttl}) {
    configureOnce(once: true, key: key, ttl: ttl);
    return this;
  }

  /// Enables or disables refresh behavior for once props.
  MergeProp<T> fresh([bool value = true]) {
    refresh(value);
    return this;
  }
}
