/// Represents an error that occurred during browser automation or setup.
///
/// Used to signal issues like failed downloads, inability to find elements,
/// or problems communicating with the WebDriver server.
class BrowserException implements Exception {
  /// A message describing the error.
  final String message;

  /// The underlying error or exception that caused this [BrowserException], if any.
  final dynamic cause;

  /// Creates a [BrowserException] with a descriptive [message] and an optional [cause].
  BrowserException(this.message, [this.cause]);

  /// Returns a string representation of the exception, including the message
  /// and the cause if available.
  @override
  String toString() {
    if (cause != null) {
      return 'BrowserException: $message (Cause: $cause)';
    }
    return 'BrowserException: $message';
  }
}

/// An error indicating that an operation did not complete within the expected time limit.
///
/// Distinct from [TimeoutException] which is an [Exception]. This is typically
/// used for unrecoverable timeout situations.
class TimeoutException extends BrowserException {
  /// A message describing the browser error.

  /// The timeout duration that was exceeded, if available.
  final Duration? timeout;

  TimeoutException(super.message, [this.timeout]);

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
