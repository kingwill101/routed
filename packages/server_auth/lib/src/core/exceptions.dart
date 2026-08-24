/// Exception used for framework-agnostic auth flow failures.
class AuthFlowException implements Exception {
  /// Creates an exception carrying the stable flow error [code].
  AuthFlowException(this.code);

  /// Stable machine-readable code for the failed authentication flow.
  final String code;

  /// Returns the exception in its stable diagnostic form.
  @override
  String toString() => 'AuthFlowException($code)';
}
