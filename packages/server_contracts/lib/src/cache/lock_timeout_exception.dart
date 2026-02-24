class LockTimeoutException implements Exception {
  LockTimeoutException(this.message);

  final String message;

  @override
  String toString() => 'LockTimeoutException: $message';
}
