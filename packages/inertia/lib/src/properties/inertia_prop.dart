library;

import 'dart:async';

import '../property_context.dart';

/// Defines the core property interfaces used by Inertia props.
///
/// These interfaces let the resolver determine when and how a prop should
/// resolve or merge.
///
/// ```dart
/// class Always<T> implements InertiaProp {
///   Always(this.value);
///   final T value;
///
///   @override
///   FutureOr<T> resolve(String key, PropertyContext context) => value;
///
///   @override
///   bool shouldInclude(String key, PropertyContext context) => true;
/// }
/// ```
abstract class InertiaProp {
  /// Resolves the property value based on the [context].
  FutureOr<dynamic> resolve(String key, PropertyContext context);

  /// Whether this property should be included in the response.
  bool shouldInclude(String key, PropertyContext context);
}

/// Marker interface for props that participate in client-side merging.
abstract class MergeableProp {
  /// Whether the prop should be merged.
  bool get shouldMerge;

  /// Whether the prop should be merged deeply.
  bool get shouldDeepMerge;

  /// Whether appends should be applied at the root level.
  bool get appendsAtRoot;

  /// Whether prepends should be applied at the root level.
  bool get prependsAtRoot;

  /// The paths to append to during merge.
  List<String> get appendsAtPaths;

  /// The paths to prepend to during merge.
  List<String> get prependsAtPaths;

  /// The keys to match on for merge semantics.
  List<String> get matchesOn;
}

/// Marker interface for props that resolve on deferred requests.
abstract class DeferrableProp {
  /// Whether the prop should defer resolution.
  bool get shouldDefer;

  /// The deferred group name.
  String get group;
}

/// Marker interface for props that resolve once.
abstract class OnceableProp {
  /// Whether the prop should resolve only once.
  bool get shouldResolveOnce;

  /// Whether the prop should refresh on demand.
  bool get shouldRefresh;

  /// The optional key used to identify once values.
  String? get onceKey;

  /// The optional time-to-live for once values.
  Duration? get ttl;
}
