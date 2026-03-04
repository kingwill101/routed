import 'dart:async';

import 'package:meta/meta.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart' show EngineRoute;
import 'package:routed/src/engine/events/request.dart';
import 'package:routed/src/engine/events/route.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed_core/routed_core.dart' show Signal;

export 'package:routed_core/src/events/signals.dart'
    show
        Signal,
        SignalHandlerEntry,
        SignalHandlerKey,
        SignalSenderMatcher,
        SignalSubscription,
        UnhandledSignalError;

class RequestSignals {
  RequestSignals(EventManager manager)
    : started = Signal<RequestStartedEvent>(
        name: 'routed.request.started',
        manager: manager,
        senderMatcher: _matchesRequestSender,
      ),
      finished = Signal<RequestFinishedEvent>(
        name: 'routed.request.finished',
        manager: manager,
        senderMatcher: _matchesRequestSender,
      ),
      routeMatched = Signal<RouteMatchedEvent>(
        name: 'routed.request.route_matched',
        manager: manager,
        senderMatcher: _matchesRequestSender,
      ),
      routingError = Signal<RoutingErrorEvent>(
        name: 'routed.request.routing_error',
        manager: manager,
        senderMatcher: _matchesRequestSender,
      ),
      afterRouting = Signal<AfterRoutingEvent>(
        name: 'routed.request.after_routing',
        manager: manager,
        senderMatcher: _matchesRequestSender,
      );

  final Signal<RequestStartedEvent> started;
  final Signal<RequestFinishedEvent> finished;
  final Signal<RouteMatchedEvent> routeMatched;
  final Signal<RoutingErrorEvent> routingError;
  final Signal<AfterRoutingEvent> afterRouting;
}

class SignalHub {
  SignalHub(this.manager) : requests = RequestSignals(manager) {
    _subscriptions = [
      manager.listen<RequestStartedEvent>(
        (event) => requests.started.dispatch(
          event,
          sender: RequestSignalSender(context: event.context),
        ),
      ),
      manager.listen<RequestFinishedEvent>(
        (event) => requests.finished.dispatch(
          event,
          sender: RequestSignalSender(context: event.context),
        ),
      ),
      manager.listen<RouteMatchedEvent>(
        (event) => requests.routeMatched.dispatch(
          event,
          sender: RequestSignalSender(
            context: event.context,
            route: event.route,
          ),
        ),
      ),
      manager.listen<RoutingErrorEvent>(
        (event) => requests.routingError.dispatch(
          event,
          sender: RequestSignalSender(
            context: event.context,
            route: event.route,
          ),
        ),
      ),
      manager.listen<AfterRoutingEvent>(
        (event) => requests.afterRouting.dispatch(
          event,
          sender: RequestSignalSender(
            context: event.context,
            route: event.route,
          ),
        ),
      ),
    ];
  }

  final EventManager manager;
  final RequestSignals requests;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
  }
}

bool _matchesRequestSender(Object? expected, Object? actual) {
  if (expected == null) {
    return true;
  }
  if (identical(expected, actual)) {
    return true;
  }
  if (actual is RequestSignalSender) {
    if (expected is EngineContext) {
      return identical(expected, actual.context);
    }
    if (expected is EngineRoute) {
      final route = actual.route;
      return route != null && identical(expected, route);
    }
  }
  return false;
}

/// Describes the origin of a request signal dispatch, including the
/// [EngineContext] and optional [EngineRoute].
@immutable
class RequestSignalSender {
  const RequestSignalSender({required this.context, this.route});

  final EngineContext context;
  final EngineRoute? route;
}
