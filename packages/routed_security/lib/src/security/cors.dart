import 'dart:io';

/// Immutable CORS policy used by header application helpers.
final class CorsPolicy {
  const CorsPolicy({
    required this.enabled,
    required this.allowedOrigins,
    required this.allowedMethods,
    required this.allowedHeaders,
    required this.allowCredentials,
    required this.maxAge,
    required this.exposedHeaders,
  });

  final bool enabled;
  final List<String> allowedOrigins;
  final List<String> allowedMethods;
  final List<String> allowedHeaders;
  final bool allowCredentials;
  final int? maxAge;
  final List<String> exposedHeaders;
}

/// Applies CORS headers according to [policy].
///
/// Returns `false` when the request fails policy checks.
bool applyCorsHeaders(
  HttpHeaders requestHeaders,
  HttpHeaders responseHeaders,
  CorsPolicy policy,
) {
  if (!policy.enabled) {
    return true;
  }

  final origin = requestHeaders.value('Origin');
  String? allowOrigin;

  if (policy.allowedOrigins.contains('*')) {
    if (policy.allowCredentials && origin != null) {
      allowOrigin = origin;
      responseHeaders.add(HttpHeaders.varyHeader, 'Origin');
    } else {
      allowOrigin = '*';
    }
  } else if (origin != null && policy.allowedOrigins.contains(origin)) {
    allowOrigin = origin;
    responseHeaders.add(HttpHeaders.varyHeader, 'Origin');
  } else {
    return false;
  }

  responseHeaders.set(HttpHeaders.accessControlAllowOriginHeader, allowOrigin);

  if (policy.allowCredentials && allowOrigin != '*') {
    responseHeaders.set(HttpHeaders.accessControlAllowCredentialsHeader, 'true');
  }

  final requestedMethod = requestHeaders.value(
    HttpHeaders.accessControlRequestMethodHeader,
  );

  if (requestedMethod != null &&
      policy.allowedMethods.isNotEmpty &&
      !policy.allowedMethods.contains(requestedMethod)) {
    return false;
  }

  responseHeaders.set(
    HttpHeaders.accessControlAllowMethodsHeader,
    policy.allowedMethods.join(', '),
  );

  final requestedHeaders =
      requestHeaders[HttpHeaders.accessControlRequestHeadersHeader];

  if (policy.allowedHeaders.isNotEmpty) {
    responseHeaders.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      policy.allowedHeaders.join(', '),
    );
  } else if (requestedHeaders != null && requestedHeaders.isNotEmpty) {
    responseHeaders.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      requestedHeaders.join(', '),
    );
  }

  if (policy.maxAge != null) {
    responseHeaders.set(
      HttpHeaders.accessControlMaxAgeHeader,
      policy.maxAge!.toString(),
    );
  }

  if (policy.exposedHeaders.isNotEmpty) {
    responseHeaders.set(
      HttpHeaders.accessControlExposeHeadersHeader,
      policy.exposedHeaders.join(', '),
    );
  }

  return true;
}
