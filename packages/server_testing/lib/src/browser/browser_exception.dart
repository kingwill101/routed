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
