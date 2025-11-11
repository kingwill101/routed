import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart';

import '../../events/event.dart' show Event;

/// Event fired before route matching begins.
///
/// This event is emitted when a request arrives but before the engine attempts
/// to match it to any registered routes. Listeners can use this to log incoming
/// requests, modify the request context, or perform pre-routing validation.
///
/// Example:
/// ```dart
/// eventManager.listen<BeforeRoutingEvent>((event) {
///   final path = event.context.request.uri.path;
///   print('Incoming request: ${event.context.request.method} $path');
/// });
/// ```
final class BeforeRoutingEvent extends Event {
  /// The engine context for the current request.
  ///
  /// Provides access to the request, response, and container for this request.
  final EngineContext context;

  /// Creates a new before routing event.
  BeforeRoutingEvent(this.context) : super();
}

/// Event fired when a route is successfully matched.
///
/// This event is emitted after a route has been matched to the request but
/// before the route's handler is executed. Listeners can use this to log
/// matched routes, perform route-specific setup, or modify the context before
/// handler execution.
///
/// Example:
/// ```dart
/// eventManager.listen<RouteMatchedEvent>((event) {
///   final routeName = event.route.name ?? 'unnamed';
///   print('Matched route: $routeName (${event.route.path})');
///
///   // Add route information to context
///   event.context.set('route_name', routeName);
/// });
/// ```
final class RouteMatchedEvent extends Event {
  /// The engine context for the current request.
  ///
  /// Provides access to the request, response, and container for this request.
  final EngineContext context;

  /// The matched route.
  ///
  /// Contains the route's path, method, handler, middleware, and parameters.
  final EngineRoute route;

  /// Creates a new route matched event.
  RouteMatchedEvent(this.context, this.route) : super();
}

/// Event fired when no matching route is found.
///
/// This event is emitted when a request cannot be matched to any registered
/// route, including fallback routes. Listeners can use this for custom 404
/// handling, logging unmatched requests, or implementing dynamic routing.
///
/// Example:
/// ```dart
/// eventManager.listen<RouteNotFoundEvent>((event) {
///   final path = event.context.request.uri.path;
///   final method = event.context.request.method;
///   print('404: $method $path not found');
///
///   // Track 404s in analytics
///   analytics.trackNotFound(path);
/// });
/// ```
final class RouteNotFoundEvent extends Event {
  /// The engine context for the current request.
  ///
  /// Provides access to the request, response, and container for this request.
  final EngineContext context;

  /// Creates a new route not found event.
  RouteNotFoundEvent(this.context) : super();
}

/// Event fired after a route handler has completed.
///
/// This event is emitted after the route handler has finished executing,
/// regardless of whether it completed successfully or threw an error.
/// Listeners can use this for logging, cleanup, performance tracking,
/// or response modification.
///
/// Example:
/// ```dart
/// eventManager.listen<AfterRoutingEvent>((event) {
///   final duration = DateTime.now().difference(event.context.get('start_time'));
///   final status = event.context.response.statusCode;
///
///   print('Request completed in ${duration.inMilliseconds}ms (status: $status)');
///
///   if (event.error != null) {
///     print('Error occurred: ${event.error}');
///   }
/// });
/// ```
final class AfterRoutingEvent extends Event {
  /// The engine context for the current request.
  ///
  /// Provides access to the request, response, and container for this request.
  final EngineContext context;

  /// The route that was handled, if any.
  ///
  /// This is `null` if no route was matched or if the event fires before matching.
  final EngineRoute? route;

  /// Any error that occurred during routing, if any.
  ///
  /// This is `null` if the request was handled successfully without errors.
  final Object? error;

  /// Creates a new after routing event.
  AfterRoutingEvent(this.context, {this.route, this.error}) : super();
}

/// Event fired when a route handler throws an error.
///
/// This event is emitted when an error occurs during route handler execution,
/// including errors in middleware. Listeners can use this for centralized
/// error logging, reporting, or custom error responses.
///
/// Example:
/// ```dart
/// eventManager.listen<RoutingErrorEvent>((event) {
///   final error = event.error;
///   final path = event.context.request.uri.path;
///
///   // Log the error with context
///   logger.error('Error handling $path: $error', event.stackTrace);
///
///   // Report to error tracking service
///   errorTracker.captureException(error, stackTrace: event.stackTrace);
/// });
/// ```
final class RoutingErrorEvent extends Event {
  /// The engine context for the current request.
  ///
  /// Provides access to the request, response, and container for this request.
  final EngineContext context;

  /// The route being handled when the error occurred, or `null` if no route
  /// matched (for example, when global middleware threw during a 404).
  final EngineRoute? route;

  /// The error that occurred.
  ///
  /// This can be any type of error or exception thrown during route handling.
  final Object error;

  /// The stack trace for the error.
  ///
  /// Provides the call stack at the point where the error was thrown.
  final StackTrace stackTrace;

  /// Creates a new routing error event.
  RoutingErrorEvent(this.context, this.route, this.error, this.stackTrace)
    : super();
}
