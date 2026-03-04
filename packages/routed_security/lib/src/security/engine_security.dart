/// Configuration for Cross-Origin Resource Sharing (CORS).
class CorsConfig {
  /// Whether CORS is enabled.
  final bool enabled;

  /// List of allowed origin domains.
  final List<String> allowedOrigins;

  /// List of allowed HTTP methods for cross-origin requests.
  final List<String> allowedMethods;

  /// List of allowed request headers.
  final List<String> allowedHeaders;

  /// Whether credentials (cookies, authorization headers) are allowed.
  final bool allowCredentials;

  /// Maximum time in seconds that preflight responses can be cached.
  final int? maxAge;

  /// List of headers that browsers are allowed to access.
  final List<String> exposedHeaders;

  const CorsConfig({
    this.enabled = false,
    this.allowedOrigins = const ['*'],
    this.allowedMethods = const [
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH',
      'OPTIONS',
    ],
    this.allowedHeaders = const [],
    this.allowCredentials = false,
    this.maxAge,
    this.exposedHeaders = const [],
  });
}

/// Configuration for engine security features.
class EngineSecurityFeatures {
  /// Whether CSRF protection is enabled.
  final bool csrfProtection;

  /// Name of the cookie used to store the CSRF token.
  final String csrfCookieName;

  /// Content Security Policy header value.
  final String? csp;

  /// Whether to add the `X-Content-Type-Options: nosniff` header.
  final bool xContentTypeOptionsNoSniff;

  /// Maximum age in seconds for HTTP Strict Transport Security (HSTS).
  final int? hstsMaxAge;

  /// Value for the `X-Frame-Options` header.
  final String? xFrameOptions;

  /// Maximum request size in bytes.
  final int maxRequestSize;

  /// CORS configuration.
  final CorsConfig cors;

  const EngineSecurityFeatures({
    this.csrfProtection = true,
    this.csrfCookieName = 'csrf_token',
    this.csp,
    this.xContentTypeOptionsNoSniff = false,
    this.hstsMaxAge,
    this.xFrameOptions,
    this.maxRequestSize = 1024 * 1024 * 10,
    this.cors = const CorsConfig(),
  });

  EngineSecurityFeatures copyWith({
    bool? csrfProtection,
    String? csrfCookieName,
    String? csp,
    bool? xContentTypeOptionsNoSniff,
    int? hstsMaxAge,
    String? xFrameOptions,
    int? maxRequestSize,
    CorsConfig? cors,
  }) {
    return EngineSecurityFeatures(
      csrfProtection: csrfProtection ?? this.csrfProtection,
      csrfCookieName: csrfCookieName ?? this.csrfCookieName,
      csp: csp ?? this.csp,
      xContentTypeOptionsNoSniff:
          xContentTypeOptionsNoSniff ?? this.xContentTypeOptionsNoSniff,
      hstsMaxAge: hstsMaxAge ?? this.hstsMaxAge,
      xFrameOptions: xFrameOptions ?? this.xFrameOptions,
      maxRequestSize: maxRequestSize ?? this.maxRequestSize,
      cors: cors ?? this.cors,
    );
  }
}
