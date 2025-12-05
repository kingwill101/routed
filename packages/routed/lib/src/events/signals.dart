import 'dart:async';

import 'package:meta/meta.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart' show EngineRoute;
import 'package:routed/src/engine/events/request.dart';
import 'package:routed/src/engine/events/route.dart';
import 'package:routed/src/events/event.dart';
import 'package:routed/src/events/event_manager.dart';

/// Lightweight wrapper around [EventManager] that mimics Django-like signals.
///
/// Handlers can [connect] and [disconnect]; when a signal dispatches, handlers
/// are invoked sequentially. Registrations support optional de-duplication keys,
/// sender scoping, and return a [SignalSubscription] for disposable lifecycle
/// management. Exceptions are caught and re-published as [UnhandledSignalError]
/// events for observability.
class Signal<T extends Event> {
  Signal({required this.name, required EventManager manager})
    : _manager = manager;

  final String name;
  final EventManager _manager;

  final Map<SignalHandlerKey<T>, SignalHandlerEntry<T>> _handlers = {};

  SignalSubscription<T> connect(
    FutureOr<void> Function(T event) handler, {
    Object? key,
    Object? sender,
  }) {
    final handlerKey = SignalHandlerKey<T>(
      handler: key == null ? handler : null,
      key: key,
    );
    final entry = SignalHandlerEntry(
      handler: handler,
      sender: sender,
      key: key,
    );
    final previous = _handlers[handlerKey];
    if (previous != null) {
      previous.active = false;
    }
    _handlers[handlerKey] = entry;
    return SignalSubscription<T>(_handlers, handlerKey, entry);
  }

  void disconnect(FutureOr<void> Function(T event)? handler, {Object? key}) {
    if (key == null && handler == null) {
      throw ArgumentError(
        'Either a handler reference or key must be provided to disconnect.',
      );
    }
    final handlerKey = SignalHandlerKey<T>(
      handler: key == null ? handler : null,
      key: key,
    );
    final entry = _handlers.remove(handlerKey);
    entry?.active = false;
  }

  Future<void> dispatch(T event, {Object? sender}) async {
    final entries = List<SignalHandlerEntry<T>>.from(_handlers.values);
    for (final entry in entries) {
      if (!entry.active) continue;
      if (!_matchesSender(entry.sender, sender)) {
        continue;
      }
      try {
        await Future.sync(() => entry.handler(event));
      } catch (error, stack) {
        _manager.publish(
          UnhandledSignalError(
            name: name,
            event: event,
            key: entry.key,
            sender: sender,
            error: error,
            stack: stack,
          ),
        );
      }
    }
  }
}

/// Emitted when a signal handler fails.
final class UnhandledSignalError extends Event {
  UnhandledSignalError({
    required this.name,
    required this.event,
    required this.error,
    required this.stack,
    this.key,
    this.sender,
  });

  final String name;
  final Event event;
  final Object? key;
  final Object? sender;
  final Object error;
  final StackTrace stack;
}

class RequestSignals {
  RequestSignals(EventManager manager)
    : started = Signal<RequestStartedEvent>(
        name: 'routed.request.started',
        manager: manager,
      ),
      finished = Signal<RequestFinishedEvent>(
        name: 'routed.request.finished',
        manager: manager,
      ),
      routeMatched = Signal<RouteMatchedEvent>(
        name: 'routed.request.route_matched',
        manager: manager,
      ),
      routingError = Signal<RoutingErrorEvent>(
        name: 'routed.request.routing_error',
        manager: manager,
      ),
      afterRouting = Signal<AfterRoutingEvent>(
        name: 'routed.request.after_routing',
        manager: manager,
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

bool _matchesSender(Object? expected, Object? actual) {
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

class SignalHandlerKey<T extends Event> {
  SignalHandlerKey({required this.handler, required this.key}) {
    if (key == null && handler == null) {
      throw ArgumentError('Either handler or key must be provided.');
    }
  }

  final FutureOr<void> Function(T event)? handler;
  final Object? key;

  @override
  bool operator ==(Object other) {
    if (other is! SignalHandlerKey<T>) return false;
    if (key != null || other.key != null) {
      return key != null && other.key != null && other.key == key;
    }
    return identical(other.handler, handler);
  }

  @override
  int get hashCode => key?.hashCode ?? identityHashCode(handler);
}

class SignalHandlerEntry<T extends Event> {
  SignalHandlerEntry({
    required this.handler,
    required this.sender,
    required this.key,
  });

  final FutureOr<void> Function(T event) handler;
  final Object? sender;
  final Object? key;
  bool active = true;
}

final class SignalSubscription<T extends Event> {
  SignalSubscription(this._handlers, this._key, this._entry);

  final Map<SignalHandlerKey<T>, SignalHandlerEntry<T>> _handlers;
  final SignalHandlerKey<T> _key;
  final SignalHandlerEntry<T> _entry;

  Object? get key => _entry.key;
  Object? get sender => _entry.sender;

  Future<void> cancel() async {
    final current = _handlers[_key];
    if (identical(current, _entry)) {
      _handlers.remove(_key);
    }
    _entry.active = false;
  }
}

/// Describes the origin of a request signal dispatch, including the
/// [EngineContext] and optional [EngineRoute].
@immutable
class RequestSignalSender {
  const RequestSignalSender({required this.context, this.route});

  final EngineContext context;
  final EngineRoute? route;
}
