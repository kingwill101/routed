import 'dart:async';

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

/// Resolves then sanitizes a redirect candidate using callback precedence.
///
/// This combines [resolveRedirectCandidate] + [sanitizeRedirectUrl] for
/// adapter runtimes that receive payload and query maps.
String? resolveAndSanitizeRedirectCandidate(
  Map<String, dynamic> payload,
  Map<String, String> queryParameters, {
  required Uri requestUri,
  String? fallbackHost,
  String? fallbackScheme,
  String payloadCallbackKey = 'callbackUrl',
  String payloadRedirectKey = 'redirect',
  String queryCallbackKey = 'callbackUrl',
}) {
  final candidate = resolveRedirectCandidate(
    payload,
    queryParameters,
    payloadCallbackKey: payloadCallbackKey,
    payloadRedirectKey: payloadRedirectKey,
    queryCallbackKey: queryCallbackKey,
  );
  return sanitizeRedirectUrl(
    candidate,
    requestUri: requestUri,
    fallbackHost: fallbackHost,
    fallbackScheme: fallbackScheme,
  );
}

/// Resolves and sanitizes redirect values using callback precedence plus an
/// optional external resolver.
///
/// The flow is:
/// 1. Resolve candidate from payload/query via [resolveRedirectCandidate].
/// 2. Sanitize candidate for same-origin safety.
/// 3. Invoke [resolveRedirect] with sanitized candidate.
/// 4. Sanitize resolved value again (or fallback to candidate when null).
Future<String?> resolveAndSanitizeRedirectWithResolver(
  Map<String, dynamic> payload,
  Map<String, String> queryParameters, {
  required Uri requestUri,
  required FutureOr<String?> Function(String? candidate) resolveRedirect,
  String? fallbackHost,
  String? fallbackScheme,
  String payloadCallbackKey = 'callbackUrl',
  String payloadRedirectKey = 'redirect',
  String queryCallbackKey = 'callbackUrl',
}) async {
  final candidate = resolveAndSanitizeRedirectCandidate(
    payload,
    queryParameters,
    requestUri: requestUri,
    fallbackHost: fallbackHost,
    fallbackScheme: fallbackScheme,
    payloadCallbackKey: payloadCallbackKey,
    payloadRedirectKey: payloadRedirectKey,
    queryCallbackKey: queryCallbackKey,
  );
  final resolved = await Future<String?>.value(resolveRedirect(candidate));
  return sanitizeRedirectUrl(
    resolved ?? candidate,
    requestUri: requestUri,
    fallbackHost: fallbackHost,
    fallbackScheme: fallbackScheme,
  );
}
