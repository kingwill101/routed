/// Exception used for framework-agnostic auth flow failures.
class AuthFlowException implements Exception {
  AuthFlowException(this.code);

  final String code;

  @override
  String toString() => 'AuthFlowException($code)';
}
