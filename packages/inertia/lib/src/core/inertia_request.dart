import '../core/headers.dart';
import '../property_context.dart';

/// Represents an Inertia request with parsed headers and context
class InertiaRequest {
  const InertiaRequest({
    required this.headers,
    required this.url,
    required this.method,
    this.body,
  });

  /// Original request headers
  final Map<String, String> headers;

  /// Request URL
  final String url;

  /// HTTP method
  final String method;

  /// Request body
  final dynamic body;

  /// Check if this is an Inertia request
  bool get isInertia => InertiaHeaderUtils.isInertiaRequest(headers);

  /// Get Inertia version
  String? get version => InertiaHeaderUtils.getVersion(headers);

  /// Check if this is a partial reload
  bool get isPartialReload => InertiaHeaderUtils.isPartialReload(headers);

  /// Get partial data
  List<String>? get partialData => InertiaHeaderUtils.getPartialData(headers);

  /// Get partial component
  String? get partialComponent =>
      InertiaHeaderUtils.getPartialComponent(headers);

  /// Get reset keys
  List<String>? get resetKeys => InertiaHeaderUtils.getResetKeys(headers);

  /// Create context for property resolution
  PropertyContext createContext({
    List<String> requestedProps = const [],
    List<String> requestedDeferredGroups = const [],
    String? onceKey,
    bool Function(String)? shouldIncludeProp,
  }) {
    return PropertyContext(
      headers: headers,
      isPartialReload: isPartialReload,
      requestedProps: requestedProps,
      requestedDeferredGroups: requestedDeferredGroups,
      onceKey: onceKey,
      shouldIncludeProp: shouldIncludeProp,
    );
  }

  /// Create partial reload context
  PropertyContext createPartialContext(List<String> requestedProps) {
    return PropertyContext.partial(
      headers: headers,
      requestedProps: requestedProps,
    );
  }

  /// Create deferred context
  PropertyContext createDeferredContext(List<String> requestedGroups) {
    return PropertyContext.deferred(
      headers: headers,
      requestedDeferredGroups: requestedGroups,
    );
  }
}
