part of 'context.dart';

extension ContextShortcuts on EngineContext {
  /// Returns [value] when it is non-null; otherwise throws a [NotFoundError].
  ///
  /// The error is recorded on the context so middleware and logging observers
  /// can react to it before the 404 response is returned.
  T requireFound<T>(T? value, {String? message}) {
    if (value != null) {
      return value;
    }
    final error = NotFoundError(message: message ?? 'Not found.');
    (_errors ??= <EngineError>[]).add(error);
    throw error;
  }

  /// Awaits the [resolver] and returns its value, throwing a [NotFoundError]
  /// when the resolved value is null.
  Future<T> fetchOr404<T>(
    FutureOr<T?> Function() resolver, {
    String? message,
  }) async {
    final result = await resolver();
    return requireFound(result, message: message);
  }
}
