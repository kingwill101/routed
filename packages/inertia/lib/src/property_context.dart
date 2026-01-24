import 'core/headers.dart';

/// Context for property resolution in Inertia requests
class PropertyContext {
  PropertyContext({
    required this.headers,
    this.isPartialReload = false,
    this.requestedProps = const [],
    this.requestedDeferredGroups = const [],
    List<String>? resetKeys,
    this.onceKey,
    bool Function(String key)? shouldIncludeProp,
  }) : resetKeys =
           resetKeys ?? InertiaHeaderUtils.getResetKeys(headers) ?? const [],
       shouldIncludeProp = shouldIncludeProp ?? ((key) => true);

  PropertyContext.partial({
    required this.headers,
    required this.requestedProps,
    this.requestedDeferredGroups = const [],
    List<String>? resetKeys,
    this.onceKey,
    bool Function(String key)? shouldIncludeProp,
  }) : isPartialReload = true,
       resetKeys =
           resetKeys ?? InertiaHeaderUtils.getResetKeys(headers) ?? const [],
       shouldIncludeProp = shouldIncludeProp ?? ((key) => true);

  PropertyContext.deferred({
    required this.headers,
    this.requestedProps = const [],
    required this.requestedDeferredGroups,
    List<String>? resetKeys,
    this.onceKey,
    bool Function(String key)? shouldIncludeProp,
  }) : isPartialReload = false,
       resetKeys =
           resetKeys ?? InertiaHeaderUtils.getResetKeys(headers) ?? const [],
       shouldIncludeProp = shouldIncludeProp ?? ((key) => true);

  /// The original request headers
  final Map<String, String> headers;

  /// Whether this is a partial reload request
  final bool isPartialReload;

  /// List of requested properties for partial reload
  final List<String> requestedProps;

  /// List of requested deferred prop groups
  final List<String> requestedDeferredGroups;

  /// List of reset keys for merge props
  final List<String> resetKeys;

  /// Request key for once properties
  final String? onceKey;

  /// Whether property should be included in response
  final bool Function(String key) shouldIncludeProp;

  /// Check if this is an Inertia request
  bool get isInertiaRequest => InertiaHeaderUtils.isInertiaRequest(headers);

  /// Get Inertia version
  String? get inertiaVersion => InertiaHeaderUtils.getVersion(headers);

  /// Get partial data
  List<String>? get partialData => InertiaHeaderUtils.getPartialData(headers);

  /// Get partial component
  String? get partialComponent =>
      InertiaHeaderUtils.getPartialComponent(headers);
}
