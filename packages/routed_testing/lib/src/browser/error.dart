class TimeoutError extends Error {
  final String message;
  final Duration? timeout;

  TimeoutError(this.message, [this.timeout]);

  @override
  String toString() {
    if (timeout != null) {
      return 'TimeoutError: $message (${timeout!.inSeconds}s)';
    }
    return 'TimeoutError: $message';
  }
}

class BrowserError implements Exception {
  final String message;
  final dynamic cause;
  final StackTrace? stackTrace;

  BrowserError(this.message, [this.cause, this.stackTrace]);

  @override
  String toString() {
    final buffer = StringBuffer('BrowserError: $message');
    if (cause != null) {
      buffer.write('\nCause: $cause');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}