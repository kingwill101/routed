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
