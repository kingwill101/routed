/// Thrown when a lock cannot be acquired before its wait deadline.
class LockTimeoutException implements Exception {
  /// Creates an exception with a diagnostic [message].
  LockTimeoutException(this.message);

  /// Explanation of why lock acquisition timed out.
  final String message;

  @override
  String toString() => 'LockTimeoutException: $message';
}
