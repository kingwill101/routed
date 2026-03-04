import 'event.dart' show Event;

/// Event fired before route matching begins.
base class BeforeRoutingEvent<TContext> extends Event {
  BeforeRoutingEvent(this.context) : super();

  /// The request context for the current request.
  final TContext context;
}

/// Event fired when a route is successfully matched.
base class RouteMatchedEvent<TContext, TRoute> extends Event {
  RouteMatchedEvent(this.context, this.route) : super();

  /// The request context for the current request.
  final TContext context;

  /// The matched route.
  final TRoute route;
}

/// Event fired when no matching route is found.
base class RouteNotFoundEvent<TContext> extends Event {
  RouteNotFoundEvent(this.context) : super();

  /// The request context for the current request.
  final TContext context;
}

/// Event fired after a route handler has completed.
base class AfterRoutingEvent<TContext, TRoute> extends Event {
  AfterRoutingEvent(this.context, {this.route, this.error}) : super();

  /// The request context for the current request.
  final TContext context;

  /// The route that was handled, if any.
  final TRoute? route;

  /// Any error that occurred during routing, if any.
  final Object? error;
}

/// Event fired when a route handler throws an error.
base class RoutingErrorEvent<TContext, TRoute> extends Event {
  RoutingErrorEvent(this.context, this.route, this.error, this.stackTrace)
    : super();

  /// The request context for the current request.
  final TContext context;

  /// The route being handled when the error occurred, if any.
  final TRoute? route;

  /// The error that occurred.
  final Object error;

  /// The stack trace for the error.
  final StackTrace stackTrace;
}
