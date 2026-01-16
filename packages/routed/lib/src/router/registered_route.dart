import 'package:routed/src/router/middleware_exclusions.dart';
import 'package:routed/src/router/types.dart';

/// Represents a route that has been registered in the Router.
/// This will be converted into an [EngineRoute] when we call [router.build()].
class RegisteredRoute {
  final String method;
  String path;
  final RouteHandler handler;

  /// Route-level middlewares (only declared on this route).
  final List<Middleware> routeMiddlewares;

  /// The final list of middlewares after merging parent group + route.
  late List<Middleware> finalMiddlewares;

  /// Middleware exclusions configured on this route.
  final MiddlewareExclusions exclusions = MiddlewareExclusions();

  /// Final exclusions after merging group/route exclusions.
  late MiddlewareExclusions finalExclusions;

  /// Name of the route, used for "named route" features.
  String? name;

  Map<String, dynamic> constraints;

  RegisteredRoute({
    required this.method,
    required this.path,
    required this.handler,
    this.routeMiddlewares = const [],
    this.name,
    Map<String, dynamic>? constraints,
  }) : constraints = Map<String, dynamic>.from(constraints ?? const {});

  void excludeMiddlewares(Iterable<Object> middlewares) {
    exclusions.addAll(middlewares);
  }

  @override
  String toString() {
    final mwCount = finalMiddlewares.isEmpty ? 0 : finalMiddlewares.length;
    return '[$method] $path with name ${name ?? "(no name)"} [middlewares: $mwCount]';
  }
}
