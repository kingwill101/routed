part of 'engine.dart';

/// Observes an error before or after the engine invokes error handlers.
typedef EngineErrorObserver =
    FutureOr<void> Function(
      EngineContext context,
      Object error,
      StackTrace stackTrace,
    );

/// Handles an error of type [T] and reports whether it was handled.
typedef EngineErrorHandler<T extends Object> =
    FutureOr<bool> Function(
      EngineContext context,
      T error,
      StackTrace stackTrace,
    );

/// Stores ordered error observers and typed handlers for an engine.
class ErrorHandlingRegistry {
  /// Creates an empty error handling registry.
  ErrorHandlingRegistry() : _before = [], _handlers = [], _after = [];

  ErrorHandlingRegistry._({
    required List<EngineErrorObserver> before,
    required List<_TypedErrorHandler> handlers,
    required List<EngineErrorObserver> after,
  }) : _before = before,
       _handlers = handlers,
       _after = after;

  final List<EngineErrorObserver> _before;
  final List<_TypedErrorHandler> _handlers;
  final List<EngineErrorObserver> _after;

  /// Adds an observer that runs before typed handlers.
  void addBefore(EngineErrorObserver observer) {
    _before.add(observer);
  }

  /// Adds an observer that runs after typed handlers.
  void addAfter(EngineErrorObserver observer) {
    _after.add(observer);
  }

  /// Adds a typed [handler] to the registry.
  void addHandler<T extends Object>(EngineErrorHandler<T> handler) {
    _handlers.add(
      _TypedErrorHandler(
        matches: (error) => error is T,
        handler: (ctx, error, stack) => handler(ctx, error as T, stack),
      ),
    );
  }

  /// Runs all registered before-error observers.
  Future<void> runBefore(
    EngineContext context,
    Object error,
    StackTrace stackTrace, {
    void Function(Object error, StackTrace stackTrace)? onHookError,
  }) async {
    for (final observer in _before) {
      await _invokeObserver(observer, context, error, stackTrace, onHookError);
    }
  }

  /// Invokes handlers until one reports that it handled the error.
  Future<bool> handle(
    EngineContext context,
    Object error,
    StackTrace stackTrace, {
    void Function(Object error, StackTrace stackTrace)? onHookError,
  }) async {
    for (final handler in _handlers) {
      if (!handler.matches(error)) continue;
      final handled = await handler.invoke(
        context,
        error,
        stackTrace,
        onHookError,
      );
      if (handled) {
        return true;
      }
    }
    return false;
  }

  /// Runs all registered after-error observers.
  Future<void> runAfter(
    EngineContext context,
    Object error,
    StackTrace stackTrace, {
    void Function(Object error, StackTrace stackTrace)? onHookError,
  }) async {
    for (final observer in _after) {
      await _invokeObserver(observer, context, error, stackTrace, onHookError);
    }
  }

  /// Creates an independent copy of this registry.
  ErrorHandlingRegistry clone() {
    return ErrorHandlingRegistry._(
      before: List.of(_before),
      handlers: _handlers.map((handler) => handler.copy()).toList(),
      after: List.of(_after),
    );
  }

  Future<void> _invokeObserver(
    EngineErrorObserver observer,
    EngineContext context,
    Object error,
    StackTrace stackTrace,
    void Function(Object error, StackTrace stackTrace)? onHookError,
  ) async {
    try {
      await Future.sync(() => observer(context, error, stackTrace));
    } catch (hookError, hookStack) {
      onHookError?.call(hookError, hookStack);
    }
  }
}

class _TypedErrorHandler {
  _TypedErrorHandler({
    required bool Function(Object error) matches,
    required _AnyErrorHandler handler,
  }) : _matches = matches,
       _handler = handler;

  final bool Function(Object error) _matches;
  final _AnyErrorHandler _handler;

  bool matches(Object error) => _matches(error);

  Future<bool> invoke(
    EngineContext context,
    Object error,
    StackTrace stackTrace,
    void Function(Object error, StackTrace stackTrace)? onHookError,
  ) async {
    try {
      final result = await Future.sync(
        () => _handler(context, error, stackTrace),
      );
      return result;
    } catch (hookError, hookStack) {
      onHookError?.call(hookError, hookStack);
      return false;
    }
  }

  _TypedErrorHandler copy() {
    return _TypedErrorHandler(matches: _matches, handler: _handler);
  }
}

typedef _AnyErrorHandler =
    FutureOr<bool> Function(
      EngineContext context,
      Object error,
      StackTrace stackTrace,
    );
