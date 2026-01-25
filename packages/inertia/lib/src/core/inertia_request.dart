library;

import '../core/inertia_header_utils.dart';
import '../property_context.dart';

/// Defines a parsed request wrapper for Inertia headers and context helpers.
///
/// Use [InertiaRequest] to read Inertia metadata from raw HTTP headers and to
/// build [PropertyContext] instances for prop resolution.
///
/// ```dart
/// final request = InertiaRequest(
///   headers: requestHeaders,
///   url: '/dashboard',
///   method: 'GET',
/// );
/// final context = request.createContext();
/// ```
class InertiaRequest {
  /// Creates an Inertia request wrapper from raw HTTP data.
  ///
  /// The [body] is stored as-is so callers can pass through framework-specific
  /// request payloads.
  const InertiaRequest({
    required this.headers,
    required this.url,
    required this.method,
    this.body,
  });

  /// The original request headers.
  final Map<String, String> headers;

  /// The request URL as a string.
  final String url;

  /// The HTTP method for this request.
  final String method;

  /// The request body, if available.
  final dynamic body;

  /// Whether this request is an Inertia request.
  bool get isInertia => InertiaHeaderUtils.isInertiaRequest(headers);

  /// The Inertia asset version, if provided.
  String? get version => InertiaHeaderUtils.getVersion(headers);

  /// Whether this request represents a partial reload.
  bool get isPartialReload => InertiaHeaderUtils.isPartialReload(headers);

  /// The requested partial prop keys, if any.
  List<String>? get partialData => InertiaHeaderUtils.getPartialData(headers);

  /// The excluded partial prop keys, if any.
  List<String>? get partialExcept =>
      InertiaHeaderUtils.getPartialExcept(headers);

  /// The partial reload component name, if any.
  String? get partialComponent =>
      InertiaHeaderUtils.getPartialComponent(headers);

  /// The merge reset keys, if any.
  List<String>? get resetKeys => InertiaHeaderUtils.getResetKeys(headers);

  /// The error bag name, if any.
  String? get errorBag => InertiaHeaderUtils.getErrorBag(headers);

  /// The once-prop exclusions, if any.
  List<String>? get exceptOnceProps =>
      InertiaHeaderUtils.getExceptOnceProps(headers);

  /// The merge intent string, if any.
  String? get mergeIntent => InertiaHeaderUtils.getMergeIntent(headers);

  /// Creates a [PropertyContext] for resolving props.
  ///
  /// When [requestedProps] or [requestedExceptProps] are omitted, the headers
  /// on this request are used instead.
  ///
  /// ```dart
  /// final context = request.createContext(
  ///   requestedDeferredGroups: ['feed'],
  /// );
  /// ```
  PropertyContext createContext({
    List<String> requestedProps = const [],
    List<String> requestedExceptProps = const [],
    List<String> requestedDeferredGroups = const [],
    String? onceKey,
    bool Function(String)? shouldIncludeProp,
  }) {
    final resolvedRequestedProps = requestedProps.isEmpty
        ? (partialData ?? const [])
        : requestedProps;
    final resolvedExceptProps = requestedExceptProps.isEmpty
        ? (partialExcept ?? const [])
        : requestedExceptProps;
    return PropertyContext(
      headers: headers,
      isPartialReload: isPartialReload,
      requestedProps: resolvedRequestedProps,
      requestedExceptProps: resolvedExceptProps,
      requestedDeferredGroups: requestedDeferredGroups,
      onceKey: onceKey,
      shouldIncludeProp: shouldIncludeProp,
    );
  }

  /// Creates a partial reload [PropertyContext] with explicit prop lists.
  ///
  /// ```dart
  /// final context = request.createPartialContext(
  ///   ['user', 'stats'],
  ///   requestedExceptProps: ['flash'],
  /// );
  /// ```
  PropertyContext createPartialContext(
    List<String> requestedProps, {
    List<String> requestedExceptProps = const [],
  }) {
    return PropertyContext.partial(
      headers: headers,
      requestedProps: requestedProps,
      requestedExceptProps: requestedExceptProps,
    );
  }

  /// Creates a deferred [PropertyContext] for the requested groups.
  ///
  /// ```dart
  /// final context = request.createDeferredContext(['feed']);
  /// ```
  PropertyContext createDeferredContext(List<String> requestedGroups) {
    return PropertyContext.deferred(
      headers: headers,
      requestedDeferredGroups: requestedGroups,
    );
  }
}
