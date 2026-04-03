/// Represents the result of attempting to match an HTTP request to a route.
///
/// [T] is the concrete route type used by the caller.
class RouteMatch<T> {
  /// Whether the request successfully matched this route.
  final bool matched;

  /// Whether the route path matched but the HTTP method did not.
  final bool isMethodMismatch;

  /// The route that was matched, if any.
  final T? route;

  /// Creates a new route match result.
  RouteMatch({
    required this.matched,
    required this.isMethodMismatch,
    this.route,
  });
}
