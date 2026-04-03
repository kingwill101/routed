/// Strongly typed policy used to materialize response security headers.
class SecurityHeaderPolicy {
  const SecurityHeaderPolicy({
    this.csp,
    required this.xContentTypeOptionsNoSniff,
    this.hstsMaxAge,
    this.xFrameOptions,
  });

  final String? csp;
  final bool xContentTypeOptionsNoSniff;
  final int? hstsMaxAge;
  final String? xFrameOptions;
}

/// Builds HTTP security headers from [policy].
Map<String, String> buildSecurityHeaders(SecurityHeaderPolicy policy) {
  final headers = <String, String>{};

  if (policy.csp != null) {
    headers['Content-Security-Policy'] = policy.csp!;
  }
  if (policy.xContentTypeOptionsNoSniff) {
    headers['X-Content-Type-Options'] = 'nosniff';
  }
  if (policy.hstsMaxAge != null) {
    headers['Strict-Transport-Security'] =
        'max-age=${policy.hstsMaxAge}; includeSubDomains; preload';
  }
  if (policy.xFrameOptions != null) {
    headers['X-Frame-Options'] = policy.xFrameOptions!;
  }

  return headers;
}
