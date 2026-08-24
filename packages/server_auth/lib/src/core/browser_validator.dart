import 'dart:io';

import 'browser.dart';

/// Comprehensive browser-request validation result.
class BrowserValidationResult {
  /// Creates a successful result with no error code.
  const BrowserValidationResult.valid() : valid = true, errorCode = null;

  /// Creates a failed result with the stable [errorCode].
  const BrowserValidationResult.invalid(this.errorCode) : valid = false;

  /// Whether the request passed browser protection.
  final bool valid;

  /// Stable failure code, or null for a valid result.
  final String? errorCode;

  /// Whether this result represents a successful validation.
  bool get isValid => valid;
}

/// Typed cookie security configuration for auth cookies.
class AuthCookiePolicy {
  /// Creates cookie settings with secure, HTTP-only, lax-SameSite defaults.
  ///
  /// [development] is a convenient alternative that relaxes only [secure].
  const AuthCookiePolicy({
    this.httpOnly = true,
    this.secure = true,
    this.sameSite = SameSite.lax,
    this.path = '/',
    this.domain,
    this.maxAge,
  });

  /// Whether cookies should be HTTP-only (not accessible via JavaScript).
  final bool httpOnly;

  /// Whether cookies should only be sent over HTTPS.
  final bool secure;

  /// SameSite cookie attribute.
  final SameSite sameSite;

  /// Cookie path.
  final String path;

  /// Optional cookie domain.
  final String? domain;

  /// Optional max age in seconds.
  final int? maxAge;

  /// Returns a copy with selected fields replaced.
  ///
  /// Set [clearDomain] or [clearMaxAge] to null out the corresponding
  /// nullable field; omitting them preserves the existing value.
  AuthCookiePolicy copyWith({
    bool? httpOnly,
    bool? secure,
    SameSite? sameSite,
    String? path,
    String? domain,
    int? maxAge,
    bool clearDomain = false,
    bool clearMaxAge = false,
  }) {
    return AuthCookiePolicy(
      httpOnly: httpOnly ?? this.httpOnly,
      secure: secure ?? this.secure,
      sameSite: sameSite ?? this.sameSite,
      path: path ?? this.path,
      domain: clearDomain ? null : (domain ?? this.domain),
      maxAge: clearMaxAge ? null : (maxAge ?? this.maxAge),
    );
  }

  /// Safe production defaults.
  static const AuthCookiePolicy production = AuthCookiePolicy(
    httpOnly: true,
    secure: true,
  );

  /// Development defaults (allows HTTP).
  static const AuthCookiePolicy development = AuthCookiePolicy(
    httpOnly: true,
    secure: false,
  );
}

/// Comprehensive browser-request validator for auth routes.
///
/// This validator combines multiple defense layers:
/// - Origin header validation
/// - Fetch Metadata site checks; mode and destination headers are observed
///   but do not currently affect the decision
/// - Referrer header validation as fallback
/// - Trusted-origin policy enforcement
/// - Content-Type validation for state-changing requests
class AuthBrowserProtectionValidator {
  /// Creates a validator from browser [options] and cookie policy settings.
  ///
  /// [cookiePolicy] is carried as configuration for adapters but is not
  /// consulted by [validate]. The default allowed MIME types are JSON,
  /// URL-encoded forms, and multipart forms.
  const AuthBrowserProtectionValidator({
    required this.options,
    this.cookiePolicy = AuthCookiePolicy.production,
    this.allowedContentTypes = const {
      'application/json',
      'application/x-www-form-urlencoded',
      'multipart/form-data',
    },
  });

  /// Browser protection options.
  final AuthBrowserProtectionOptions options;

  /// Cookie security policy.
  final AuthCookiePolicy cookiePolicy;

  /// Allowed content types for state-changing requests.
  final Set<String> allowedContentTypes;

  /// Validates a browser request and returns the first failed check.
  ///
  /// Disabled protection returns valid. Otherwise method, Origin, Fetch
  /// Metadata, optional Referrer fallback, and Content-Type checks run in that
  /// order. Method comparison is case-insensitive; Content-Type is checked
  /// only for methods other than GET and HEAD.
  ///
  /// [requestUri] is the URI of the incoming request, [headers] provides its
  /// headers, and [method] is the HTTP method.
  BrowserValidationResult validate({
    required Uri requestUri,
    required HttpHeaders headers,
    required String method,
  }) {
    if (!options.enabled) {
      return const BrowserValidationResult.valid();
    }

    final normalizedMethod = method.trim().toUpperCase();
    final methodAllowed = options.allowedMethods.any(
      (allowed) => allowed.trim().toUpperCase() == normalizedMethod,
    );
    if (!methodAllowed) {
      return const BrowserValidationResult.invalid('method_not_allowed');
    }

    // 1. Validate Origin header
    final originResult = _validateOrigin(headers, requestUri);
    if (!originResult.isValid) return originResult;

    // 2. Validate Fetch Metadata
    final fetchResult = _validateFetchMetadata(headers, requestUri);
    if (!fetchResult.isValid) return fetchResult;

    // 3. Validate Referrer as fallback
    final referrerResult = _validateReferrer(headers, requestUri);
    if (!referrerResult.isValid) return referrerResult;

    // 4. Validate Content-Type for state-changing requests
    if (normalizedMethod != 'GET' && normalizedMethod != 'HEAD') {
      final contentTypeResult = _validateContentType(headers);
      if (!contentTypeResult.isValid) return contentTypeResult;
    }

    return const BrowserValidationResult.valid();
  }

  /// Validates the Origin header against allowed origins.
  BrowserValidationResult _validateOrigin(HttpHeaders headers, Uri requestUri) {
    final origin = headers.value('origin')?.trim();
    final requestOrigin = _originOf(requestUri);

    if (origin == null) {
      if (options.requireOrigin) {
        return const BrowserValidationResult.invalid('missing_origin');
      }
      return const BrowserValidationResult.valid();
    }

    final allowed = _isOriginAllowed(origin, requestOrigin);
    if (!allowed) {
      return const BrowserValidationResult.invalid('invalid_origin');
    }

    return const BrowserValidationResult.valid();
  }

  /// Validates Fetch Metadata headers.
  ///
  /// Missing metadata is allowed for non-browser clients. Same-origin and
  /// same-site requests pass; cross-site and cross-origin requests require an
  /// explicitly allowed Origin. Fetch mode and destination are read but do not
  /// currently affect the decision.
  BrowserValidationResult _validateFetchMetadata(
    HttpHeaders headers,
    Uri requestUri,
  ) {
    if (!options.enforceFetchMetadata) {
      return const BrowserValidationResult.valid();
    }

    final rawFetchSite = headers.value('sec-fetch-site')?.trim();
    final fetchSite = rawFetchSite?.toLowerCase();
    final rawFetchMode = headers.value('sec-fetch-mode')?.trim();
    final fetchMode = rawFetchMode?.toLowerCase();
    final rawFetchDest = headers.value('sec-fetch-dest')?.trim();
    final fetchDest = rawFetchDest?.toLowerCase();

    // If no Fetch Metadata headers, allow (non-browser clients)
    if (fetchSite == null && fetchMode == null && fetchDest == null) {
      return const BrowserValidationResult.valid();
    }

    // Cross-site requests must establish an explicitly allowed origin. A
    // missing Origin header cannot be treated as a successful origin check.
    if (fetchSite == 'cross-site') {
      final origin = headers.value('origin')?.trim();
      if (origin == null || !_isOriginAllowed(origin, _originOf(requestUri))) {
        return const BrowserValidationResult.invalid('cross_site_request');
      }
    }

    // Same-origin and same-site are always allowed
    if (fetchSite == 'same-origin' || fetchSite == 'same-site') {
      return const BrowserValidationResult.valid();
    }

    // Cross-origin requests need origin validation - already checked above
    if (fetchSite == 'cross-origin') {
      final origin = headers.value('origin')?.trim();
      if (origin == null || !_isOriginAllowed(origin, _originOf(requestUri))) {
        return const BrowserValidationResult.invalid('cross_site_request');
      }
    }

    return const BrowserValidationResult.valid();
  }

  /// Validates the Referer header as a fallback for missing Origin.
  ///
  /// Malformed or absent referrers pass. A mismatch is rejected only when
  /// [AuthBrowserProtectionOptions.enforceReferrer] is enabled.
  BrowserValidationResult _validateReferrer(
    HttpHeaders headers,
    Uri requestUri,
  ) {
    // Referer validation is optional and only used when Origin is missing
    if (headers.value('origin') != null) {
      return const BrowserValidationResult.valid();
    }

    final referrer = headers.value('referer')?.trim();
    if (referrer == null || referrer.isEmpty) {
      return const BrowserValidationResult.valid();
    }

    final referrerUri = Uri.tryParse(referrer);
    if (referrerUri == null) {
      return const BrowserValidationResult.valid();
    }

    final requestOrigin = _originOf(requestUri);
    if (requestOrigin == null) {
      return const BrowserValidationResult.valid();
    }

    final referrerOrigin = _originOf(referrerUri);
    if (referrerOrigin == null) {
      return const BrowserValidationResult.valid();
    }

    if (referrerOrigin != requestOrigin && options.enforceReferrer) {
      return const BrowserValidationResult.invalid('referrer_mismatch');
    }

    return const BrowserValidationResult.valid();
  }

  /// Validates Content-Type for state-changing requests.
  ///
  /// Parameters are stripped and the MIME type is lowercased. Values in
  /// [allowedContentTypes] are not normalized by this class, so callers should
  /// provide lowercase values.
  BrowserValidationResult _validateContentType(HttpHeaders headers) {
    if (!options.requireContentType) {
      return const BrowserValidationResult.valid();
    }

    final contentType = headers.value('content-type')?.trim() ?? '';
    if (contentType.isEmpty) {
      return const BrowserValidationResult.invalid('missing_content_type');
    }

    final mimeType = contentType.split(';').first.trim().toLowerCase();
    if (allowedContentTypes.contains(mimeType)) {
      return const BrowserValidationResult.valid();
    }

    return const BrowserValidationResult.invalid('unsupported_content_type');
  }

  /// Checks if an origin is allowed by the protection policy.
  bool _isOriginAllowed(String origin, String? requestOrigin) {
    // Check if origin matches the request origin (same-origin)
    if (requestOrigin != null) {
      final parsedOrigin = Uri.tryParse(origin);
      if (parsedOrigin != null) {
        final normalizedOrigin = _originOf(parsedOrigin);
        if (normalizedOrigin != null && normalizedOrigin == requestOrigin) {
          return true;
        }
      }
    }

    // Check against explicitly allowed origins
    for (final allowed in options.allowedOrigins) {
      final allowedUri = Uri.tryParse(allowed);
      if (allowedUri == null) continue;
      final normalizedAllowed = _originOf(allowedUri);
      final parsedOrigin = Uri.tryParse(origin);
      if (parsedOrigin == null) continue;
      final normalizedOrigin = _originOf(parsedOrigin);
      if (normalizedAllowed != null &&
          normalizedOrigin != null &&
          normalizedAllowed == normalizedOrigin) {
        return true;
      }
    }

    // Check against trusted origins
    for (final trusted in options.trustedOrigins) {
      final trustedUri = Uri.tryParse(trusted);
      if (trustedUri == null) continue;
      final normalizedTrusted = _originOf(trustedUri);
      final parsedOrigin = Uri.tryParse(origin);
      if (parsedOrigin == null) continue;
      final normalizedOrigin = _originOf(parsedOrigin);
      if (normalizedTrusted != null &&
          normalizedOrigin != null &&
          normalizedTrusted == normalizedOrigin) {
        return true;
      }
    }

    return false;
  }

  /// Extracts and normalizes the origin from a URI.
  static String? _originOf(Uri? uri, {bool strict = false}) {
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    if (strict &&
        (uri.userInfo.isNotEmpty ||
            uri.query.isNotEmpty ||
            uri.fragment.isNotEmpty ||
            (uri.path.isNotEmpty && uri.path != '/'))) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final defaultPort = scheme == 'https' ? 443 : 80;
    final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host.toLowerCase()}$port';
  }
}
