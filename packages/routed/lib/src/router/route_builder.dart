import 'package:routed/src/openapi/operation.dart';
import 'package:routed/src/router/registered_route.dart';
import 'package:routed/src/router/router.dart';
import 'package:routed/src/router/types.dart';

import 'router_group_builder.dart';

/// The `RouteBuilder` class is returned by methods like `router.get(...)`
/// to allow for additional configuration of the route, such as setting its name.
class RouteBuilder {
  /// The registered route that this builder is configuring.
  final RegisteredRoute _route;

  /// The router instance that this builder is associated with.
  final Router _router;

  /// Constructs a `RouteBuilder` with the given registered route and router.
  RouteBuilder(this._route, this._router);

  /// Sets the name of the route.
  ///
  /// The [routeName] parameter specifies the name to be assigned to the route.
  /// Returns the current instance of `RouteBuilder` to allow for method chaining.
  RouteBuilder name(String routeName) {
    _route.name = routeName;
    return this;
  }

  /// Adds or merges constraints to the route.
  ///
  /// The [newConstraints] parameter is a map containing the constraints to be added or merged.
  /// Returns the current instance of `RouteBuilder` to allow for method chaining.
  RouteBuilder constraints(Map<String, dynamic> newConstraints) {
    _route.constraints.addAll(newConstraints);
    return this;
  }

  /// Excludes middleware from this route.
  RouteBuilder withoutMiddleware(Iterable<Object> middlewares) {
    _route.excludeMiddlewares(middlewares);
    return this;
  }

  /// Creates a new router group with the specified path, middlewares, and builder function.
  ///
  /// The [path] parameter specifies the base path for the group.
  /// The [middlewares] parameter is a list of middleware functions to be applied to the group.
  /// The [builder] parameter is a function that takes a `Router` instance and defines the routes within the group.
  /// Returns an instance of `RouterGroupBuilder` for further configuration of the group.
  RouterGroupBuilder group({
    String path = '',
    List<Middleware> middlewares = const [],
    void Function(Router)? builder,
  }) {
    return _router.group(
      path: path,
      middlewares: middlewares,
      builder: builder,
    );
  }

  /// Attach OpenAPI operation metadata for spec generation.
  ///
  /// The provided [configure] callback can populate summaries, tags, responses,
  /// and other OpenAPI fields. Multiple invocations merge metadata.
  RouteBuilder openApi(
    void Function(OpenApiOperationBuilder builder) configure,
  ) {
    final builder = OpenApiOperationBuilder();
    configure(builder);
    final spec = builder.build();
    final existing = _route.constraints['openapi'];
    if (existing is Map<String, Object?>) {
      final merged = Map<String, Object?>.from(existing);
      merged.addAll(spec.toJson());
      _route.constraints['openapi'] = merged;
    } else {
      _route.constraints['openapi'] = spec.toJson();
    }
    return this;
  }
}
