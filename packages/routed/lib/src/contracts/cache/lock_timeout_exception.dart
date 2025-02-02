/// Exception thrown when a lock times out.
class LockTimeoutException implements Exception {
  /// The error message associated with this exception.
  final String message;

  /// Creates a [LockTimeoutException] with the given error [message].
  LockTimeoutException(this.message);

  @override
  String toString() => 'LockTimeoutException: $message';
}
