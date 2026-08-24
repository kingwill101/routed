import 'package:routed_core/routed_core.dart' show EngineRoute;
import 'package:routed_core/src/engine/engine.dart' show EngineRoute;
import 'package:routed_core/src/router/route_metadata.dart';
import 'package:routed_core/src/router/types.dart';

/// Represents a route that has been registered in the Router.
/// This will be converted into an [EngineRoute] when we call [router.build()].
class RegisteredRoute {
  /// Creates a [RegisteredRoute].
  RegisteredRoute({
    required this.method,
    required this.path,
    required this.handler,
    this.routeMiddlewares = const [],
    this.name,
    this.sourceFile,
    this.sourceLine,
    this.sourceColumn,
    this.schema,
    Map<String, dynamic>? constraints,
    RouteMetadata? metadata,
  }) : constraints = Map<String, dynamic>.from(constraints ?? const {}),
       metadata = metadata ?? RouteMetadata();

  /// The HTTP method registered for this route.
  final String method;

  /// The path pattern registered for this route.
  String path;

  /// The handler invoked when this route matches.
  final RouteHandler handler;

  /// Route-level middlewares (only declared on this route).
  final List<Middleware> routeMiddlewares;

  /// The final list of middlewares after merging parent group + route.
  late List<Middleware> finalMiddlewares;

  /// Name of the route, used for "named route" features.
  String? name;

  /// The constraints applied while matching this route.
  Map<String, dynamic> constraints;

  /// Generic typed metadata attached to the route.
  final RouteMetadata metadata;

  /// Optional API schema metadata for this route.
  final Object? schema;

  /// Source file where the route registration call occurred.
  final String? sourceFile;

  /// 1-based source line where the route registration call occurred.
  final int? sourceLine;

  /// 1-based source column where the route registration call occurred.
  final int? sourceColumn;

  @override
  String toString() {
    final mwCount = finalMiddlewares.isEmpty ? 0 : finalMiddlewares.length;
    return '[$method] $path with name ${name ?? "(no name)"} [middlewares: $mwCount]';
  }
}
