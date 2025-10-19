import 'dart:async';

import 'package:routed/src/context/context.dart';

abstract class ErrorObserver {
  FutureOr<void> onError(
    EngineContext context,
    Object error,
    StackTrace stackTrace,
  );
}

class ErrorObserverRegistry {
  final List<ErrorObserver> _observers = [];

  void addObserver(ErrorObserver observer) {
    _observers.add(observer);
  }

  Future<void> notify(
    EngineContext context,
    Object error,
    StackTrace stackTrace,
  ) async {
    for (final observer in _observers) {
      try {
        await observer.onError(context, error, stackTrace);
      } catch (_) {
        // Swallow observer errors to avoid cascading failures.
      }
    }
  }

  bool get hasObservers => _observers.isNotEmpty;
}
