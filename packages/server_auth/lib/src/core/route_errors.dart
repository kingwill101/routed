import 'dart:io';

final RegExp _publicAuthErrorCode = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// Returns a bounded, identifier-shaped error code safe for HTTP responses.
///
/// Provider callbacks may produce arbitrary diagnostic strings. Adapters must
/// use this helper before returning callback or flow failures so paths,
/// credentials, and exception messages cannot become public response data.
String sanitizeAuthErrorCode(String? code, {String fallback = 'auth_error'}) {
  final candidate = code?.trim();
  if (candidate == null || !_publicAuthErrorCode.hasMatch(candidate)) {
    return fallback;
  }
  return candidate;
}

/// Resolves the HTTP status code for a canonical auth error [code].
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
