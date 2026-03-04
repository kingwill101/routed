import 'dart:async';

import 'package:meta/meta.dart';

import 'event_manager.dart';
import 'request_events.dart';
import 'routing_events.dart';
import 'signals.dart';

bool matchesRequestSignalSender<TContext, TRoute>(
  Object? expected,
  Object? actual,
) {
  if (expected == null) {
    return true;
  }
  if (identical(expected, actual)) {
    return true;
  }
  if (actual is RequestSignalSender<TContext, TRoute>) {
    if (expected is TContext) {
      return identical(expected, actual.context);
    }
    if (expected is TRoute) {
      final route = actual.route;
      return route != null && identical(expected, route);
    }
  }
  return false;
}

/// Describes the origin of a request signal dispatch.
@immutable
final class RequestSignalSender<TContext, TRoute> {
  const RequestSignalSender({required this.context, this.route});

  final TContext context;
  final TRoute? route;
}

/// Request lifecycle signals built on top of the event manager.
class RequestSignals<
  TContext,
  TRoute,
  TRequestStartedEvent extends RequestStartedEvent<TContext>,
  TRequestFinishedEvent extends RequestFinishedEvent<TContext>,
  TRouteMatchedEvent extends RouteMatchedEvent<TContext, TRoute>,
  TRoutingErrorEvent extends RoutingErrorEvent<TContext, TRoute>,
  TAfterRoutingEvent extends AfterRoutingEvent<TContext, TRoute>
> {
  RequestSignals(
    EventManager manager, {
    this.startedName = 'routed.request.started',
    this.finishedName = 'routed.request.finished',
    this.routeMatchedName = 'routed.request.route_matched',
    this.routingErrorName = 'routed.request.routing_error',
    this.afterRoutingName = 'routed.request.after_routing',
    SignalSenderMatcher? senderMatcher,
  }) : started = Signal<TRequestStartedEvent>(
         name: startedName,
         manager: manager,
         senderMatcher:
             senderMatcher ?? matchesRequestSignalSender<TContext, TRoute>,
       ),
       finished = Signal<TRequestFinishedEvent>(
         name: finishedName,
         manager: manager,
         senderMatcher:
             senderMatcher ?? matchesRequestSignalSender<TContext, TRoute>,
       ),
       routeMatched = Signal<TRouteMatchedEvent>(
         name: routeMatchedName,
         manager: manager,
         senderMatcher:
             senderMatcher ?? matchesRequestSignalSender<TContext, TRoute>,
       ),
       routingError = Signal<TRoutingErrorEvent>(
         name: routingErrorName,
         manager: manager,
         senderMatcher:
             senderMatcher ?? matchesRequestSignalSender<TContext, TRoute>,
       ),
       afterRouting = Signal<TAfterRoutingEvent>(
         name: afterRoutingName,
         manager: manager,
         senderMatcher:
             senderMatcher ?? matchesRequestSignalSender<TContext, TRoute>,
       );

  final String startedName;
  final String finishedName;
  final String routeMatchedName;
  final String routingErrorName;
  final String afterRoutingName;

  final Signal<TRequestStartedEvent> started;
  final Signal<TRequestFinishedEvent> finished;
  final Signal<TRouteMatchedEvent> routeMatched;
  final Signal<TRoutingErrorEvent> routingError;
  final Signal<TAfterRoutingEvent> afterRouting;
}

/// Bridges request lifecycle events to request lifecycle signals.
class SignalHub<
  TContext,
  TRoute,
  TRequestStartedEvent extends RequestStartedEvent<TContext>,
  TRequestFinishedEvent extends RequestFinishedEvent<TContext>,
  TRouteMatchedEvent extends RouteMatchedEvent<TContext, TRoute>,
  TRoutingErrorEvent extends RoutingErrorEvent<TContext, TRoute>,
  TAfterRoutingEvent extends AfterRoutingEvent<TContext, TRoute>
> {
  SignalHub(
    this.manager, {
    RequestSignals<
      TContext,
      TRoute,
      TRequestStartedEvent,
      TRequestFinishedEvent,
      TRouteMatchedEvent,
      TRoutingErrorEvent,
      TAfterRoutingEvent
    >?
    requests,
    String startedName = 'routed.request.started',
    String finishedName = 'routed.request.finished',
    String routeMatchedName = 'routed.request.route_matched',
    String routingErrorName = 'routed.request.routing_error',
    String afterRoutingName = 'routed.request.after_routing',
    SignalSenderMatcher? senderMatcher,
  }) : requests =
           requests ??
           RequestSignals<
             TContext,
             TRoute,
             TRequestStartedEvent,
             TRequestFinishedEvent,
             TRouteMatchedEvent,
             TRoutingErrorEvent,
             TAfterRoutingEvent
           >(
             manager,
             startedName: startedName,
             finishedName: finishedName,
             routeMatchedName: routeMatchedName,
             routingErrorName: routingErrorName,
             afterRoutingName: afterRoutingName,
             senderMatcher: senderMatcher,
           ) {
    _subscriptions = [
      manager.listen<TRequestStartedEvent>(
        (event) => this.requests.started.dispatch(
          event,
          sender: RequestSignalSender<TContext, TRoute>(context: event.context),
        ),
      ),
      manager.listen<TRequestFinishedEvent>(
        (event) => this.requests.finished.dispatch(
          event,
          sender: RequestSignalSender<TContext, TRoute>(context: event.context),
        ),
      ),
      manager.listen<TRouteMatchedEvent>(
        (event) => this.requests.routeMatched.dispatch(
          event,
          sender: RequestSignalSender<TContext, TRoute>(
            context: event.context,
            route: event.route,
          ),
        ),
      ),
      manager.listen<TRoutingErrorEvent>(
        (event) => this.requests.routingError.dispatch(
          event,
          sender: RequestSignalSender<TContext, TRoute>(
            context: event.context,
            route: event.route,
          ),
        ),
      ),
      manager.listen<TAfterRoutingEvent>(
        (event) => this.requests.afterRouting.dispatch(
          event,
          sender: RequestSignalSender<TContext, TRoute>(
            context: event.context,
            route: event.route,
          ),
        ),
      ),
    ];
  }

  final EventManager manager;
  final RequestSignals<
    TContext,
    TRoute,
    TRequestStartedEvent,
    TRequestFinishedEvent,
    TRouteMatchedEvent,
    TRoutingErrorEvent,
    TAfterRoutingEvent
  >
  requests;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
  }
}
