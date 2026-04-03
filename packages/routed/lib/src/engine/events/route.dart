import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed_core/routed_core.dart' as core;

/// Event fired before route matching begins.
final class BeforeRoutingEvent
    extends core.BeforeRoutingEvent<EngineContext> {
  BeforeRoutingEvent(super.context);
}

/// Event fired when a route is successfully matched.
final class RouteMatchedEvent
    extends core.RouteMatchedEvent<EngineContext, EngineRoute> {
  RouteMatchedEvent(super.context, super.route);
}

/// Event fired when no matching route is found.
final class RouteNotFoundEvent
    extends core.RouteNotFoundEvent<EngineContext> {
  RouteNotFoundEvent(super.context);
}

/// Event fired after a route handler has completed.
final class AfterRoutingEvent
    extends core.AfterRoutingEvent<EngineContext, EngineRoute> {
  AfterRoutingEvent(super.context, {super.route, super.error});
}

/// Event fired when a route handler throws an error.
final class RoutingErrorEvent
    extends core.RoutingErrorEvent<EngineContext, EngineRoute> {
  RoutingErrorEvent(super.context, super.route, super.error, super.stackTrace);
}
