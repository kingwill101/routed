class BrowserException implements Exception {
  final String message;
  final dynamic cause;

  BrowserException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'BrowserException: $message (Cause: $cause)';
    }
    return 'BrowserException: $message';
  }
}
