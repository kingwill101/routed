import 'dart:io';

/// Resolves the HTTP status code for a canonical auth error [code].
int authErrorStatusCode(String code) {
  switch (code) {
    case 'unknown_provider':
      return HttpStatus.notFound;
    case 'invalid_csrf':
      return HttpStatus.forbidden;
    case 'method_not_allowed':
      return HttpStatus.methodNotAllowed;
    default:
      return HttpStatus.badRequest;
  }
}
