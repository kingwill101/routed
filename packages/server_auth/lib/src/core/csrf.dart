import 'tokens.dart' show constantTimeStringEquals;

/// Returns an existing CSRF token or generates one when missing.
///
/// Null and empty values invoke [generateToken].
String resolveCsrfToken({
  required String? existingToken,
  required String Function() generateToken,
}) {
  if (existingToken != null && existingToken.isNotEmpty) {
    return existingToken;
  }
  return generateToken();
}

/// Validates a CSRF token from header and form values.
///
/// Returns true immediately when [enforce] is false. Otherwise a non-empty
/// [expectedToken] is required, and [headerToken] takes precedence over
/// [formToken] even when the header value is empty. Comparison is constant-time.
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
  return presented != null &&
      constantTimeStringEquals(expectedToken, presented);
}
