import 'dart:async';

import 'package:meta/meta.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/engine/engine.dart' show EngineRoute;
import 'package:routed_core/src/engine/events/request.dart';
import 'package:routed_core/src/engine/events/route.dart';
import 'package:routed_core/src/events/event.dart';
import 'package:routed_core/src/events/event_manager.dart';

/// Lightweight wrapper around [EventManager] that mimics Django-like signals.
///
/// Handlers can [connect] and [disconnect]; when a signal dispatches, handlers
/// are invoked sequentially. Registrations support optional de-duplication keys,
/// sender scoping, and return a [SignalSubscription] for disposable lifecycle
/// management. Exceptions are caught and re-published as [UnhandledSignalError]
/// events for observability.
class Signal<T extends Event> {
  /// Creates a named signal backed by [manager].
  Signal({required this.name, required EventManager manager})
    : _manager = manager;

  /// The stable signal name.
  final String name;
  final EventManager _manager;

  final Map<SignalHandlerKey<T>, SignalHandlerEntry<T>> _handlers = {};

  /// Connects [handler] and returns its disposable subscription.
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

  /// Disconnects a handler or keyed registration.
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

  /// Dispatches [event] to active matching handlers.
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
  /// Creates an error event for a failed signal handler.
  UnhandledSignalError({
    required this.name,
    required this.event,
    required this.error,
    required this.stack,
    this.key,
    this.sender,
  });

  /// The signal name that failed.
  final String name;

  /// The event being dispatched when the failure occurred.
  final Event event;

  /// The optional registration key.
  final Object? key;

  /// The sender associated with the dispatch.
  final Object? sender;

  /// The thrown error.
  final Object error;

  /// The stack trace captured from the handler.
  final StackTrace stack;
}

/// Signals emitted for the engine request lifecycle.
class RequestSignals {
  /// Creates request lifecycle signals backed by [manager].
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

  /// Emitted when request processing starts.
  final Signal<RequestStartedEvent> started;

  /// Emitted when request processing finishes.
  final Signal<RequestFinishedEvent> finished;

  /// Emitted when a route matches.
  final Signal<RouteMatchedEvent> routeMatched;

  /// Emitted when routing fails.
  final Signal<RoutingErrorEvent> routingError;

  /// Emitted after routing completes.
  final Signal<AfterRoutingEvent> afterRouting;
}

/// Bridges engine events to typed request lifecycle signals.
class SignalHub {
  /// Creates a signal hub backed by [manager].
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

  /// The event manager supplying source events.
  final EventManager manager;

  /// The request lifecycle signals exposed by this hub.
  final RequestSignals requests;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  /// Cancels all subscriptions held by this hub.
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

/// A signal handler key used by Routed.
class SignalHandlerKey<T extends Event> {
  /// Creates a key from a handler reference or explicit [key].
  SignalHandlerKey({required this.handler, required this.key}) {
    if (key == null && handler == null) {
      throw ArgumentError('Either handler or key must be provided.');
    }
  }

  /// The handler reference used for identity-based registrations.
  final FutureOr<void> Function(T event)? handler;

  /// The explicit de-duplication key.
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

/// A signal handler entry used by Routed.
class SignalHandlerEntry<T extends Event> {
  /// Creates a signal handler entry.
  SignalHandlerEntry({
    required this.handler,
    required this.sender,
    required this.key,
  });

  /// The handler callback.
  final FutureOr<void> Function(T event) handler;

  /// The sender scope for this handler.
  final Object? sender;

  /// The optional de-duplication key.
  final Object? key;

  /// Whether this registration can still receive events.
  bool active = true;
}

/// A signal subscription used by Routed.
final class SignalSubscription<T extends Event> {
  /// Creates a subscription for a registered signal handler.
  SignalSubscription(this._handlers, this._key, this._entry);

  final Map<SignalHandlerKey<T>, SignalHandlerEntry<T>> _handlers;
  final SignalHandlerKey<T> _key;
  final SignalHandlerEntry<T> _entry;

  /// The explicit registration key, when one was supplied.
  Object? get key => _entry.key;

  /// The sender scope, when one was supplied.
  Object? get sender => _entry.sender;

  /// Cancels this subscription.
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
  /// Creates a sender descriptor for [context] and optional [route].
  const RequestSignalSender({required this.context, this.route});

  /// The request context that emitted the signal.
  final EngineContext context;

  /// The route associated with the signal, when available.
  final EngineRoute? route;
}
