import 'dart:async';

import 'event.dart';
import 'event_manager.dart';

typedef SignalSenderMatcher = bool Function(Object? expected, Object? actual);

bool _defaultSignalSenderMatcher(Object? expected, Object? actual) {
  if (expected == null) {
    return true;
  }
  return identical(expected, actual);
}

/// Lightweight event signal abstraction built on top of [EventManager].
class Signal<T extends Event> {
  Signal({
    required this.name,
    required EventManager manager,
    SignalSenderMatcher? senderMatcher,
  }) : _manager = manager,
       _senderMatcher = senderMatcher ?? _defaultSignalSenderMatcher;

  final String name;
  final EventManager _manager;
  final SignalSenderMatcher _senderMatcher;

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
      if (!_senderMatcher(entry.sender, sender)) {
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
