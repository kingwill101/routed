import 'dart:async';

/// A mutable UTC clock for deterministic authentication tests.
final class AuthTestClock {
  /// Creates a clock at [now].
  AuthTestClock(DateTime now) : _now = now.toUtc();

  DateTime _now;

  /// Current fixture time in UTC.
  DateTime get value => _now;

  /// Clock callback accepted by auth stores and plugins.
  DateTime call() => _now;

  /// Moves the clock forward by [duration].
  DateTime advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    return _now = _now.add(duration);
  }

  /// Replaces the current time with [value], normalized to UTC.
  void set(DateTime value) => _now = value.toUtc();
}

/// A deterministic finite sequence for test-only tokens, codes, and IDs.
///
/// Values are supplied by the test. No value from this sequence should be
/// reused as an application secret.
final class AuthTestSequence<T> {
  /// Creates a sequence consumed in insertion order.
  AuthTestSequence(Iterable<T> values) : _values = List<T>.unmodifiable(values);

  final List<T> _values;
  var _index = 0;

  /// Number of values that have not been consumed.
  int get remaining => _values.length - _index;

  /// Returns the next value or throws when the fixture is exhausted.
  T next() {
    if (_index >= _values.length) {
      throw StateError('Auth test sequence is exhausted');
    }
    return _values[_index++];
  }
}

/// A manually released gate for deterministic contention tests.
final class AuthTestGate {
  final Completer<void> _entered = Completer<void>();
  final Completer<void> _released = Completer<void>();

  /// Completes when a fixture reaches the gate.
  Future<void> get entered => _entered.future;

  /// Whether [release] has been called.
  bool get isReleased => _released.isCompleted;

  /// Waits until the test calls [release].
  Future<void> wait() {
    if (!_entered.isCompleted) _entered.complete();
    return _released.future;
  }

  /// Allows every waiter to continue.
  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

/// Captures provider delivery payloads without logging or serializing them.
///
/// The raw values remain in memory only and are exposed through [values] so a
/// test can complete the corresponding flow. [failNext] and [gateNext] make
/// provider failures and concurrent delivery easy to arrange.
final class AuthTestDeliveryLog<T> {
  final List<T> _values = <T>[];
  Object? _nextError;
  StackTrace? _nextStackTrace;
  AuthTestGate? _nextGate;

  /// Captured payloads in delivery order.
  List<T> get values => List<T>.unmodifiable(_values);

  /// Most recently captured payload.
  T get latest {
    if (_values.isEmpty) throw StateError('No auth delivery was captured');
    return _values.last;
  }

  /// Configures the next [capture] call to throw [error] after recording it.
  void failNext(Object error, [StackTrace? stackTrace]) {
    _nextError = error;
    _nextStackTrace = stackTrace;
  }

  /// Pauses the next [capture] call at [gate] after recording the payload.
  void gateNext(AuthTestGate gate) => _nextGate = gate;

  /// Records [value], then applies any configured gate or failure.
  Future<void> capture(T value) async {
    _values.add(value);
    final gate = _nextGate;
    _nextGate = null;
    if (gate != null) await gate.wait();
    final error = _nextError;
    final stackTrace = _nextStackTrace;
    _nextError = null;
    _nextStackTrace = null;
    if (error != null) {
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
    }
  }

  /// Removes every captured payload and pending behavior.
  void clear() {
    _values.clear();
    _nextError = null;
    _nextStackTrace = null;
    _nextGate = null;
  }
}

/// Runs [action] [count] times without serializing the returned futures.
Future<List<T>> runAuthTestConcurrently<T>(
  int count,
  Future<T> Function(int index) action,
) {
  if (count <= 0) {
    throw ArgumentError.value(count, 'count', 'must be positive');
  }
  return Future.wait<T>(List<Future<T>>.generate(count, action));
}
