import 'engine.dart' show EngineRoute;

/// Represents the result of attempting to match an HTTP request to a route.
///
/// This class encapsulates information about whether a route matched a request,
/// and if not, whether the failure was due to an HTTP method mismatch.
class RouteMatch {
  /// Whether the request successfully matched this route.
  ///
  /// Returns `true` if both the path and HTTP method matched, and all
  /// constraints were satisfied.
  final bool matched;

  /// Whether the route path matched but the HTTP method did not.
  ///
  /// This is useful for returning 405 Method Not Allowed responses instead of
  /// 404 Not Found when the path is correct but the method is wrong.
  final bool isMethodMismatch;

  /// The route that was matched, if any.
  ///
  /// This is `null` when [matched] is `false`.
  final EngineRoute? route;

  /// Creates a new route match result.
  ///
  /// The [matched] parameter indicates whether the route matched successfully.
  /// The [isMethodMismatch] parameter indicates whether the failure was due to
  /// an HTTP method mismatch.
  /// The [route] parameter contains the matched route when [matched] is `true`.
  RouteMatch({
    required this.matched,
    required this.isMethodMismatch,
    this.route,
  });
}
