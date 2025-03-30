/// An error indicating that an operation did not complete within the expected time limit.
///
/// Distinct from [TimeoutException] which is an [Exception]. This is typically
/// used for unrecoverable timeout situations.
class TimeoutError extends Error {
  /// A message describing the browser error.

  /// A message describing the timeout error.
  final String message;
  /// The timeout duration that was exceeded, if available.
  final Duration? timeout;

  /// Creates a [TimeoutError] with a descriptive [message] and optional [timeout] duration.
  TimeoutError(this.message, [this.timeout]);

  /// Returns a string representation including the message, cause, and stack trace if available.

  /// Returns a string representation of the timeout error, including the timeout duration if available.
  @override
  String toString() {
    if (timeout != null) {
      return 'TimeoutError: $message (${timeout!.inSeconds}s)';
    }
    return 'TimeoutError: $message';
  }
}

/// A general exception type for errors occurring during browser interactions or setup.
///
/// This serves as a base class or alternative to [BrowserException].
/// Consider consolidating with [BrowserException].
class BrowserError implements Exception {
  final String message;
  /// The underlying error or exception that caused this [BrowserError], if any.
  final dynamic cause;
  /// The stack trace associated with this error, if available.
  final StackTrace? stackTrace;

  /// Creates a [BrowserError] with a [message] and optional [cause] and [stackTrace].
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
