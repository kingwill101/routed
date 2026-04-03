/// Returns `true` for HTTP methods that do not require CSRF checks.
bool isCsrfSafeMethod(String method) {
  return method == 'GET' || method == 'HEAD' || method == 'OPTIONS';
}

/// Resolves a submitted CSRF token from headers/form payload.
String? resolveSubmittedCsrfToken({
  String? headerToken,
  String? fallbackHeaderToken,
  String? formToken,
}) {
  final header = headerToken ?? fallbackHeaderToken;
  if (header != null && header.isNotEmpty) {
    return header;
  }
  if (formToken != null && formToken.isNotEmpty) {
    return formToken;
  }
  return null;
}

/// Validates a submitted CSRF token against the session token.
bool isCsrfTokenValid({
  required String? sessionToken,
  required String? submittedToken,
}) {
  return sessionToken != null &&
      submittedToken != null &&
      submittedToken.isNotEmpty &&
      submittedToken == sessionToken;
}
