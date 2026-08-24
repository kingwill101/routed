/// Thrown when `Lock.block` cannot acquire a lock before its wait deadline.
class LockTimeoutException implements Exception {
  /// Creates an exception with a diagnostic [message].
  LockTimeoutException(this.message);

  /// Explanation of why acquisition timed out.
  final String message;

  @override
  String toString() => 'LockTimeoutException: $message';
}
