/// Builds a base URL (`scheme://host[:port]`) from [uri].
String baseUrlFromUri(
  Uri uri, {
  String defaultScheme = 'http',
  String defaultHost = 'localhost',
}) {
  final scheme = uri.scheme.isEmpty ? defaultScheme : uri.scheme;
  final host = uri.host.isEmpty ? defaultHost : uri.host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '$scheme://$host$port';
}

/// Sanitizes callback/redirect URLs to same-origin or rooted-relative values.
///
/// Returns `null` for invalid or cross-origin values.
String? sanitizeRedirectUrl(
  String? value, {
  required Uri requestUri,
  String? fallbackHost,
  String? fallbackScheme,
}) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return null;
  }

  if (!uri.isAbsolute) {
    return trimmed.startsWith('/') ? trimmed : null;
  }

  final requestHost = requestUri.host.isNotEmpty
      ? requestUri.host
      : (fallbackHost ?? '');
  final requestScheme = requestUri.scheme.isNotEmpty
      ? requestUri.scheme
      : (fallbackScheme ?? '');

  final sameHost = requestHost.isNotEmpty && uri.host == requestHost;
  final sameScheme =
      uri.scheme.isEmpty ||
      (requestScheme.isNotEmpty &&
          uri.scheme.toLowerCase() == requestScheme.toLowerCase());

  if (sameHost && sameScheme) {
    return uri.toString();
  }
  return null;
}

/// Resolves a redirect candidate using auth callback precedence:
/// payload callback key -> payload redirect key -> query callback key.
String? resolveRedirectCandidate(
  Map<String, dynamic> payload,
  Map<String, String> queryParameters, {
  String payloadCallbackKey = 'callbackUrl',
  String payloadRedirectKey = 'redirect',
  String queryCallbackKey = 'callbackUrl',
}) {
  return payload[payloadCallbackKey]?.toString() ??
      payload[payloadRedirectKey]?.toString() ??
      queryParameters[queryCallbackKey];
}
