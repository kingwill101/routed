import 'dart:io';

final RegExp _publicAuthErrorCode = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// Returns a bounded, identifier-shaped error code for HTTP responses.
///
/// [code] is trimmed and accepted only when it matches
/// `^[a-z][a-z0-9_]{0,63}$`. Invalid or missing values return [fallback]
/// unchanged, so callers should provide a safe fallback. Provider callbacks
/// may produce arbitrary diagnostic strings; this helper prevents them from
/// becoming public response data.
String sanitizeAuthErrorCode(String? code, {String fallback = 'auth_error'}) {
  final candidate = code?.trim();
  if (candidate == null || !_publicAuthErrorCode.hasMatch(candidate)) {
    return fallback;
  }
  return candidate;
}

/// Resolves the HTTP status code for a canonical auth error [code].
///
/// Unknown codes map to 400. The `unknown_provider` code maps to 404;
/// CSRF, origin, and cross-site failures map to 403; method and rate-limit
/// failures map to 405 and 429.
int authErrorStatusCode(String code) {
  switch (code) {
    case 'unknown_provider':
      return HttpStatus.notFound;
    case 'invalid_csrf':
      return HttpStatus.forbidden;
    case 'method_not_allowed':
      return HttpStatus.methodNotAllowed;
    case 'rate_limited':
      return HttpStatus.tooManyRequests;
    case 'invalid_origin':
    case 'cross_site_request':
      return HttpStatus.forbidden;
    default:
      return HttpStatus.badRequest;
  }
}
