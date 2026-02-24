/// Extracts a bearer token from an authorization header value.
///
/// Returns `null` when [headerValue] is empty, does not match [prefix], or the
/// extracted token is empty.
String? extractBearerToken(
  String? headerValue, {
  String prefix = 'Bearer ',
  bool caseSensitive = true,
}) {
  if (headerValue == null || headerValue.isEmpty) {
    return null;
  }

  if (prefix.isEmpty) {
    final token = headerValue.trim();
    return token.isEmpty ? null : token;
  }

  if (caseSensitive) {
    if (!headerValue.startsWith(prefix)) {
      return null;
    }
    final token = headerValue.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  final headerLower = headerValue.toLowerCase();
  final prefixLower = prefix.toLowerCase();
  if (!headerLower.startsWith(prefixLower)) {
    return null;
  }
  final token = headerValue.substring(prefix.length).trim();
  return token.isEmpty ? null : token;
}

/// Resolves a token from bearer header first, then cookie entries by name.
String? resolveBearerOrCookieToken({
  required String? authorizationHeader,
  required String bearerPrefix,
  required String cookieName,
  required Iterable<MapEntry<String, String>> cookies,
  bool caseSensitive = true,
}) {
  final bearer = extractBearerToken(
    authorizationHeader,
    prefix: bearerPrefix,
    caseSensitive: caseSensitive,
  );
  if (bearer != null) {
    return bearer;
  }

  for (final cookie in cookies) {
    if (cookie.key == cookieName) {
      final value = cookie.value.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}
