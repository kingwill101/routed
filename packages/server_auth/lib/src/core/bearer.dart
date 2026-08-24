/// Extracts a bearer token from an authorization header value.
///
/// Returns `null` when [headerValue] is empty, does not match [prefix], or the
/// extracted token is empty. Matching is prefix-based; the token is trimmed,
/// and only the prefix comparison becomes case-insensitive when requested.
/// An empty [prefix] treats the entire trimmed header as the token.
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

/// Builds a `WWW-Authenticate` header value for a Bearer challenge.
///
/// Empty parameters are omitted, and quotes and backslashes are escaped.
String buildBearerAuthenticateHeader({
  String? realm,
  String? error,
  String? errorDescription,
}) {
  final params = <String>[];
  if (realm != null && realm.isNotEmpty) {
    params.add('realm="${_escapeBearerHeaderValue(realm)}"');
  }
  if (error != null && error.isNotEmpty) {
    params.add('error="${_escapeBearerHeaderValue(error)}"');
  }
  if (errorDescription != null && errorDescription.isNotEmpty) {
    params.add(
      'error_description="${_escapeBearerHeaderValue(errorDescription)}"',
    );
  }
  if (params.isEmpty) {
    return 'Bearer';
  }
  return 'Bearer ${params.join(', ')}';
}

/// Resolves a token from the bearer header before cookie entries by name.
///
/// Cookie names use exact matching even when header prefix matching is
/// case-insensitive. The first matching cookie wins; an empty value returns
/// null without searching later cookies.
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

String _escapeBearerHeaderValue(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
