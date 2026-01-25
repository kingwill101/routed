library;

import '../property_context.dart';
import 'inertia_prop.dart';
import 'prop_mixins.dart';

/// Pagination metadata for scroll props.
class ScrollMetadata {
  /// Creates scroll metadata with optional navigation pointers.
  const ScrollMetadata({
    required this.pageName,
    this.previousPage,
    this.nextPage,
    this.currentPage,
  });

  /// Returns an empty metadata object with a default page name.
  factory ScrollMetadata.empty() {
    return const ScrollMetadata(pageName: 'page');
  }

  /// The query parameter name used for paging.
  final String pageName;

  /// The previous page identifier, if any.
  final Object? previousPage;

  /// The next page identifier, if any.
  final Object? nextPage;

  /// The current page identifier, if any.
  final Object? currentPage;

  /// Converts the metadata into a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'pageName': pageName,
      'previousPage': previousPage,
      'nextPage': nextPage,
      'currentPage': currentPage,
    };
  }
}

/// Resolves [ScrollMetadata] from a resolved scroll value.
typedef ScrollMetadataResolver<T> = ScrollMetadata Function(T value);

/// Defines props and metadata for infinite scroll style pagination.
///
/// ```dart
/// final props = {
///   'feed': ScrollProp(() => pageData)
///     ..defer('feed')
///     ..append('data'),
/// };
/// ```
class ScrollProp<T>
    with DefersProps, MergesProps
    implements InertiaProp, DeferrableProp, MergeableProp {
  /// Creates a scroll prop backed by [resolver].
  ///
  /// Use [wrapper] to define the prop key that holds list data and [metadata]
  /// to provide custom scroll metadata extraction.
  ScrollProp(
    this.resolver, {
    String wrapper = 'data',
    ScrollMetadataResolver<T>? metadata,
    bool defer = false,
    String? group,
  }) : _wrapper = wrapper,
       _metadataResolver = metadata {
    configureMerge(true);
    if (defer) {
      configureDeferred(deferred: true, group: group ?? 'default');
    }
  }

  /// The resolver that produces the prop value.
  final T Function() resolver;
  final String _wrapper;
  final ScrollMetadataResolver<T>? _metadataResolver;
  T? _resolved;

  /// Configures merge paths based on the client intent.
  void configureMergeIntent(String? intent) {
    if (intent == 'prepend') {
      prepend(_wrapper);
    } else {
      append(_wrapper);
    }
  }

  /// Resolves scroll metadata for the current value.
  ScrollMetadata metadata() {
    final value = _resolveValue();
    final resolver = _metadataResolver;
    if (resolver != null) {
      return resolver(value);
    }
    if (value is ScrollMetadata) {
      return value;
    }
    return ScrollMetadata.empty();
  }

  /// Resolves and caches the underlying value.
  T _resolveValue() {
    _resolved ??= resolver();
    return _resolved as T;
  }

  @override
  /// Whether this prop should be included for the current [context].
  bool shouldInclude(String key, PropertyContext context) {
    return context.shouldIncludeProp(key);
  }

  @override
  /// Resolves the prop value.
  T resolve(String key, PropertyContext context) => _resolveValue();

  /// Marks this prop as deferred, optionally setting a [group].
  ScrollProp<T> defer([String? group]) {
    configureDeferred(deferred: true, group: group);
    return this;
  }

  @override
  /// Appends to a merge path and returns this prop for chaining.
  ScrollProp<T> append([Object? path, String? matchOn]) {
    super.append(path, matchOn);
    return this;
  }

  @override
  /// Prepends to a merge path and returns this prop for chaining.
  ScrollProp<T> prepend([Object? path, String? matchOn]) {
    super.prepend(path, matchOn);
    return this;
  }

  /// Adds a match-on key for merge semantics.
  ScrollProp<T> matchOn(Object? value) {
    configureMatchOn(value);
    return this;
  }

  /// Enables or disables deep merge behavior.
  ScrollProp<T> deepMerge([bool value = true]) {
    configureDeepMerge(value);
    return this;
  }
}
