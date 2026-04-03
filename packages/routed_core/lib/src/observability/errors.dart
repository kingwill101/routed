import 'dart:async';

abstract class ErrorObserver<C> {
  FutureOr<void> onError(C context, Object error, StackTrace stackTrace);
}

class ErrorObserverRegistry<C> {
  final List<ErrorObserver<C>> _observers = [];

  void addObserver(ErrorObserver<C> observer) {
    _observers.add(observer);
  }

  Future<void> notify(C context, Object error, StackTrace stackTrace) async {
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
