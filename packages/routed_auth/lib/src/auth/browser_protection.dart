import 'package:routed_core/routed_core.dart' show EngineContext;
import 'package:server_auth/server_auth.dart';

/// Checks browser-origin and Fetch Metadata headers for state-changing auth
/// requests.
///
/// OAuth and other external-provider callbacks should not call this helper:
/// those callbacks are expected to arrive from another origin and still rely
/// on provider state/nonce validation.
///
/// Returns null when the request passes every enabled check. Otherwise returns
/// one of `method_not_allowed`, `invalid_origin`, `missing_content_type`,
/// `unsupported_content_type`, `cross_site_request`, or
/// `referrer_mismatch`. Disabled checks are skipped; the method allowlist is
/// evaluated first, and a trusted origin bypasses the remaining checks. The
/// request origin and configured [AuthBrowserProtectionOptions.allowedOrigins]
/// are accepted when they match, subject to the configured content type,
/// Fetch Metadata, and Referer policies.
String? validateRoutedAuthBrowserRequest(
  EngineContext context,
  AuthBrowserProtectionOptions options,
) {
  if (!options.enabled) return null;

  // The method allowlist applies before origin trust. Trusted browser origins
  // do not gain access to HTTP methods the auth surface did not enable.
  final method = context.request.method.trim().toUpperCase();
  final methodAllowed = options.allowedMethods.any(
    (allowed) => allowed.trim().toUpperCase() == method,
  );
  if (!methodAllowed) return 'method_not_allowed';

  // Trusted origins bypass the remaining origin and browser-header checks.
  final origin = context.request.headers.value('origin')?.trim();
  if (origin != null) {
    for (final trusted in options.trustedOrigins) {
      final trustedUri = Uri.tryParse(trusted);
      if (trustedUri != null) {
        final normalizedTrusted = _originOf(trustedUri);
        final normalizedOrigin = _originOf(Uri.tryParse(origin));
        if (normalizedTrusted != null &&
            normalizedOrigin != null &&
            normalizedTrusted == normalizedOrigin) {
          return null; // Trusted origin, bypass all checks
        }
      }
    }
  }

  // Original origin validation
  final requestOrigin = _originOf(context.requestedUri);
  final allowed =
      origin != null &&
      (_matchesOrigin(origin, requestOrigin) ||
          options.allowedOrigins.any(
            (candidate) =>
                _matchesOrigin(origin, _originOf(Uri.tryParse(candidate))),
          ));

  if (origin == null) {
    if (options.requireOrigin) return 'invalid_origin';
  } else if (!allowed) {
    return 'invalid_origin';
  }

  if (options.requireContentType &&
      context.request.method.toUpperCase() != 'GET' &&
      context.request.method.toUpperCase() != 'HEAD') {
    final contentType =
        context.request.headers.value('content-type')?.trim() ?? '';
    final mimeType = contentType.split(';').first.trim().toLowerCase();
    const allowedContentTypes = {
      'application/json',
      'application/x-www-form-urlencoded',
      'multipart/form-data',
    };
    if (mimeType.isEmpty) return 'missing_content_type';
    if (!allowedContentTypes.contains(mimeType)) {
      return 'unsupported_content_type';
    }
  }

  // Fetch Metadata validation
  final fetchSite = context.request.headers.value('sec-fetch-site')?.trim();
  if (options.enforceFetchMetadata &&
      fetchSite != null &&
      fetchSite.toLowerCase() == 'cross-site' &&
      !allowed) {
    return 'cross_site_request';
  }

  // Referer validation as fallback when Origin header is absent
  if (options.enforceReferrer && origin == null) {
    final referrer = context.request.headers.value('referer')?.trim();
    if (referrer != null && referrer.isNotEmpty) {
      final referrerUri = Uri.tryParse(referrer);
      if (referrerUri != null && requestOrigin != null) {
        final referrerOrigin = _originOf(referrerUri);
        if (referrerOrigin != null && referrerOrigin != requestOrigin) {
          return 'referrer_mismatch';
        }
      }
    }
  }

  return null;
}

String? _originOf(Uri? uri, {bool strict = false}) {
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

bool _matchesOrigin(String? left, String? right) {
  if (left == null || right == null) return false;
  final normalizedLeft = _originOf(Uri.tryParse(left), strict: true);
  final normalizedRight = _originOf(Uri.tryParse(right), strict: true);
  return normalizedLeft != null && normalizedLeft == normalizedRight;
}
