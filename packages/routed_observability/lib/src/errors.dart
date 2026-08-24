import 'dart:async';

import 'package:routed_core/routed_core.dart';

/// Receives errors raised while processing a Routed request.
// ErrorObserver is intentionally a one-method extension point for applications
// that need to connect Routed errors to their own reporting system.
// ignore: one_member_abstracts
abstract class ErrorObserver {
  /// Reports [error] and its [stackTrace] for [context].
  FutureOr<void> onError(
    EngineContext context,
    Object error,
    StackTrace stackTrace,
  );
}

/// Maintains error observers and isolates observer failures from requests.
class ErrorObserverRegistry {
  final List<ErrorObserver> _observers = [];

  /// Adds [observer] to the notification list.
  void addObserver(ErrorObserver observer) {
    _observers.add(observer);
  }

  /// Notifies every registered observer about [error].
  Future<void> notify(
    EngineContext context,
    Object error,
    StackTrace stackTrace,
  ) async {
    for (final observer in _observers) {
      try {
        await observer.onError(context, error, stackTrace);
      } on Object catch (_) {
        // Swallow observer errors to avoid cascading failures.
      }
    }
  }

  /// Whether at least one observer is registered.
  bool get hasObservers => _observers.isNotEmpty;
}
