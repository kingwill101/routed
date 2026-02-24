/// Returns an existing CSRF token or generates one when missing.
String resolveCsrfToken({
  required String? existingToken,
  required String Function() generateToken,
}) {
  if (existingToken != null && existingToken.isNotEmpty) {
    return existingToken;
  }
  return generateToken();
}

/// Validates a CSRF token from header/form values.
bool validateCsrfToken({
  required String? expectedToken,
  String? headerToken,
  String? formToken,
  bool enforce = true,
}) {
  if (!enforce) {
    return true;
  }
  if (expectedToken == null || expectedToken.isEmpty) {
    return false;
  }
  final presented = headerToken ?? formToken;
  return presented != null && presented == expectedToken;
}
