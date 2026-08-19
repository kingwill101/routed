import 'package:server_auth/server_auth.dart';

import 'package:routed_core/src/context/context.dart';

/// Checks browser-origin and Fetch Metadata headers for state-changing auth
/// requests.
///
/// OAuth and other external-provider callbacks should not call this helper:
/// those callbacks are expected to arrive from another origin and still rely
/// on provider state/nonce validation.
String? validateRoutedAuthBrowserRequest(
  EngineContext context,
  AuthBrowserProtectionOptions options,
) {
  if (!options.enabled) return null;

  final origin = context.request.headers.value('origin')?.trim();
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

  final fetchSite = context.request.headers.value('sec-fetch-site')?.trim();
  if (options.enforceFetchMetadata &&
      fetchSite != null &&
      fetchSite.toLowerCase() == 'cross-site' &&
      !allowed) {
    return 'cross_site_request';
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
