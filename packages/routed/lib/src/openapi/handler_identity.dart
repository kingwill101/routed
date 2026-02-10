/// Composite identity for matching route handlers across runtime and
/// static analysis.
///
/// The build_runner generator and analyzer plugin need a stable way to
/// correlate a handler function with its route registration. At runtime
/// we may have a route name, a function reference, or just a method+path
/// pair. This class encapsulates all three and resolves to the most
/// specific available identity.
///
/// Priority order (highest to lowest):
/// 1. **Route name** — explicitly set via `.name('users.create')`
/// 2. **Function reference** — the Dart function/method name (e.g. `createUser`)
/// 3. **Method + path** — fallback using HTTP method and route path
library;

/// Identifies a route handler for cross-referencing between runtime
/// registration and static analysis.
class HandlerIdentity {
  /// Creates an identity from available components.
  ///
  /// At least one of [routeName], [functionRef], or both [method] and [path]
  /// must be provided.
  const HandlerIdentity({
    this.routeName,
    this.functionRef,
    this.method,
    this.path,
  });

  /// Creates an identity from a route name.
  const HandlerIdentity.named(String name)
    : routeName = name,
      functionRef = null,
      method = null,
      path = null;

  /// Creates an identity from a function reference name.
  const HandlerIdentity.fromFunction(String ref)
    : routeName = null,
      functionRef = ref,
      method = null,
      path = null;

  /// Creates an identity from an HTTP method and path.
  const HandlerIdentity.fromRoute(String this.method, String this.path)
    : routeName = null,
      functionRef = null;

  /// The explicit route name (e.g. `'users.create'`).
  final String? routeName;

  /// The Dart function/method name (e.g. `'createUser'`).
  ///
  /// At runtime this is typically extracted from `handler.toString()` or
  /// from the function's runtime type. The build_runner generator extracts
  /// this from the AST.
  final String? functionRef;

  /// The HTTP method (e.g. `'GET'`, `'POST'`).
  final String? method;

  /// The route path pattern (e.g. `'/users/{id}'`).
  final String? path;

  /// The canonical identity string, resolved in priority order.
  ///
  /// Returns the most specific identity available:
  /// 1. `name:users.create`
  /// 2. `fn:createUser`
  /// 3. `route:POST /users`
  String get key {
    if (routeName != null && routeName!.isNotEmpty) {
      return 'name:$routeName';
    }
    if (functionRef != null && functionRef!.isNotEmpty) {
      return 'fn:$functionRef';
    }
    if (method != null && path != null) {
      return 'route:$method $path';
    }
    return 'unknown';
  }

  /// Whether this identity has enough information to be useful.
  bool get isResolved =>
      (routeName != null && routeName!.isNotEmpty) ||
      (functionRef != null && functionRef!.isNotEmpty) ||
      (method != null && path != null);

  /// Returns `true` if this identity matches [other].
  ///
  /// Matching follows the priority chain — if both identities have a route
  /// name, that is compared. Otherwise function refs are compared, and
  /// finally method+path.
  bool matches(HandlerIdentity other) {
    // If both have route names, compare those
    if (_hasRouteName && other._hasRouteName) {
      return routeName == other.routeName;
    }
    // If both have function refs, compare those
    if (_hasFunctionRef && other._hasFunctionRef) {
      return functionRef == other.functionRef;
    }
    // If both have method+path, compare those
    if (_hasRoute && other._hasRoute) {
      return method == other.method && path == other.path;
    }
    // Cross-level: check if any available identity component matches
    if (_hasRouteName && other._hasRouteName) {
      return routeName == other.routeName;
    }
    return false;
  }

  bool get _hasRouteName => routeName != null && routeName!.isNotEmpty;
  bool get _hasFunctionRef => functionRef != null && functionRef!.isNotEmpty;
  bool get _hasRoute => method != null && path != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HandlerIdentity) return false;
    return key == other.key;
  }

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'HandlerIdentity($key)';

  /// Serializes this identity to JSON.
  Map<String, Object?> toJson() {
    return {
      if (routeName != null) 'routeName': routeName,
      if (functionRef != null) 'functionRef': functionRef,
      if (method != null) 'method': method,
      if (path != null) 'path': path,
    };
  }

  /// Deserializes from JSON.
  factory HandlerIdentity.fromJson(Map<String, Object?> json) {
    return HandlerIdentity(
      routeName: json['routeName'] as String?,
      functionRef: json['functionRef'] as String?,
      method: json['method'] as String?,
      path: json['path'] as String?,
    );
  }
}
