library;

import 'core/inertia_header_utils.dart';

/// Defines the property resolution context for Inertia requests.
///
/// [PropertyContext] determines which props resolve for full visits, partial
/// reloads, deferred groups, and once props.
///
/// ```dart
/// final context = PropertyContext(
///   headers: requestHeaders,
///   isPartialReload: true,
///   requestedProps: ['user', 'stats'],
/// );
/// ```
class PropertyContext {
  /// Creates a context with optional overrides for request-driven values.
  ///
  /// When optional parameters are omitted, this constructor reads from
  /// [headers] using [InertiaHeaderUtils].
  ///
  /// ```dart
  /// final context = PropertyContext(
  ///   headers: headers,
  ///   requestedDeferredGroups: ['feed'],
  /// );
  /// ```
  PropertyContext({
    required this.headers,
    this.isPartialReload = false,
    this.requestedProps = const [],
    List<String>? requestedExceptProps,
    this.requestedDeferredGroups = const [],
    List<String>? resetKeys,
    List<String>? exceptOnceProps,
    String? errorBag,
    String? mergeIntent,
    this.onceKey,
    bool Function(String key)? shouldIncludeProp,
  }) : resetKeys =
           resetKeys ?? InertiaHeaderUtils.getResetKeys(headers) ?? const [],
       requestedExceptProps =
           requestedExceptProps ??
           InertiaHeaderUtils.getPartialExcept(headers) ??
           const [],
       exceptOnceProps =
           exceptOnceProps ??
           InertiaHeaderUtils.getExceptOnceProps(headers) ??
           const [],
       errorBag = errorBag ?? InertiaHeaderUtils.getErrorBag(headers),
       mergeIntent = mergeIntent ?? InertiaHeaderUtils.getMergeIntent(headers),
       shouldIncludeProp =
           shouldIncludeProp ??
           ((key) => PropertyContext._defaultIncludePredicate(
             isPartialReload,
             requestedProps,
             requestedExceptProps ??
                 InertiaHeaderUtils.getPartialExcept(headers) ??
                 const [],
             key,
           ));

  /// Creates a context for a partial reload.
  ///
  /// ```dart
  /// final context = PropertyContext.partial(
  ///   headers: headers,
  ///   requestedProps: ['user'],
  /// );
  /// ```
  PropertyContext.partial({
    required this.headers,
    required this.requestedProps,
    List<String>? requestedExceptProps,
    this.requestedDeferredGroups = const [],
    List<String>? resetKeys,
    List<String>? exceptOnceProps,
    String? errorBag,
    String? mergeIntent,
    this.onceKey,
    bool Function(String key)? shouldIncludeProp,
  }) : isPartialReload = true,
       resetKeys =
           resetKeys ?? InertiaHeaderUtils.getResetKeys(headers) ?? const [],
       requestedExceptProps =
           requestedExceptProps ??
           InertiaHeaderUtils.getPartialExcept(headers) ??
           const [],
       exceptOnceProps =
           exceptOnceProps ??
           InertiaHeaderUtils.getExceptOnceProps(headers) ??
           const [],
       errorBag = errorBag ?? InertiaHeaderUtils.getErrorBag(headers),
       mergeIntent = mergeIntent ?? InertiaHeaderUtils.getMergeIntent(headers),
       shouldIncludeProp =
           shouldIncludeProp ??
           ((key) => PropertyContext._defaultIncludePredicate(
             true,
             requestedProps,
             requestedExceptProps ??
                 InertiaHeaderUtils.getPartialExcept(headers) ??
                 const [],
             key,
           ));

  /// Creates a context for deferred prop groups.
  ///
  /// ```dart
  /// final context = PropertyContext.deferred(
  ///   headers: headers,
  ///   requestedDeferredGroups: ['feed'],
  /// );
  /// ```
  PropertyContext.deferred({
    required this.headers,
    this.requestedProps = const [],
    List<String>? requestedExceptProps,
    required this.requestedDeferredGroups,
    List<String>? resetKeys,
    List<String>? exceptOnceProps,
    String? errorBag,
    String? mergeIntent,
    this.onceKey,
    bool Function(String key)? shouldIncludeProp,
  }) : isPartialReload = false,
       resetKeys =
           resetKeys ?? InertiaHeaderUtils.getResetKeys(headers) ?? const [],
       requestedExceptProps =
           requestedExceptProps ??
           InertiaHeaderUtils.getPartialExcept(headers) ??
           const [],
       exceptOnceProps =
           exceptOnceProps ??
           InertiaHeaderUtils.getExceptOnceProps(headers) ??
           const [],
       errorBag = errorBag ?? InertiaHeaderUtils.getErrorBag(headers),
       mergeIntent = mergeIntent ?? InertiaHeaderUtils.getMergeIntent(headers),
       shouldIncludeProp =
           shouldIncludeProp ??
           ((key) => PropertyContext._defaultIncludePredicate(
             false,
             requestedProps,
             requestedExceptProps ??
                 InertiaHeaderUtils.getPartialExcept(headers) ??
                 const [],
             key,
           ));

  /// The original request headers.
  final Map<String, String> headers;

  /// Whether this is a partial reload request.
  final bool isPartialReload;

  /// The requested prop keys for a partial reload.
  final List<String> requestedProps;

  /// The prop keys to exclude during a partial reload.
  final List<String> requestedExceptProps;

  /// The requested deferred prop groups.
  final List<String> requestedDeferredGroups;

  /// The merge reset keys.
  final List<String> resetKeys;

  /// The once-prop exclusions.
  final List<String> exceptOnceProps;

  /// The error bag name, if provided.
  final String? errorBag;

  /// The merge intent for infinite scroll, if provided.
  final String? mergeIntent;

  /// The request key for once properties, if provided.
  final String? onceKey;

  /// Predicate that decides whether a prop should be included.
  final bool Function(String key) shouldIncludeProp;

  /// Whether this request is an Inertia request.
  bool get isInertiaRequest => InertiaHeaderUtils.isInertiaRequest(headers);

  /// The Inertia asset version from the headers, if provided.
  String? get inertiaVersion => InertiaHeaderUtils.getVersion(headers);

  /// The requested partial prop keys, if any.
  List<String>? get partialData => InertiaHeaderUtils.getPartialData(headers);

  /// The partial reload component name, if any.
  String? get partialComponent =>
      InertiaHeaderUtils.getPartialComponent(headers);

  /// Default inclusion predicate used when [shouldIncludeProp] is not supplied.
  static bool _defaultIncludePredicate(
    bool isPartialReload,
    List<String> requestedProps,
    List<String> requestedExceptProps,
    String key,
  ) {
    if (!isPartialReload) return true;
    if (requestedProps.isNotEmpty && !requestedProps.contains(key)) {
      return false;
    }
    if (requestedExceptProps.contains(key)) return false;
    return true;
  }
}
