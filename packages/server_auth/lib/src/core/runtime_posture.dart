import 'dart:io';

/// Declares whether auth is running with production guarantees or an
/// explicitly relaxed local-development posture.
enum AuthRuntimeMode { production, localDevelopment }

/// Explicit policy for forwarded client-address headers at an auth boundary.
///
/// Production callers must choose either [AuthProxyPolicy.direct] or
/// [AuthProxyPolicy.trusted]. Routed applies this decision to its engine
/// configuration instead of inferring trust from request headers.
final class AuthProxyPolicy {
  const AuthProxyPolicy.direct()
    : trustsForwardedHeaders = false,
      forwardClientIp = false,
      proxies = const <String>[],
      headers = const <String>[],
      platformHeader = null;

  AuthProxyPolicy.trusted({
    required Iterable<String> proxies,
    this.forwardClientIp = true,
    Iterable<String> headers = const <String>['X-Forwarded-For', 'X-Real-IP'],
    String? platformHeader,
  }) : trustsForwardedHeaders = true,
       proxies = List<String>.unmodifiable(proxies.map(_normalizeProxyNetwork)),
       headers = List<String>.unmodifiable(headers.map(_normalizeHeaderName)),
       platformHeader = platformHeader == null
           ? null
           : _normalizeHeaderName(platformHeader) {
    if (this.proxies.isEmpty) {
      throw ArgumentError.value(
        this.proxies,
        'proxies',
        'must contain at least one explicit trusted address or network',
      );
    }
    if (this.headers.isEmpty) {
      throw ArgumentError.value(
        this.headers,
        'headers',
        'must contain non-empty forwarded header names',
      );
    }
  }

  /// Whether the host may inspect forwarded request headers.
  final bool trustsForwardedHeaders;

  /// Whether a trusted forwarded address may become the request client IP.
  final bool forwardClientIp;

  /// Explicit addresses or networks allowed to supply forwarded headers.
  final List<String> proxies;

  /// Forwarded client-address headers, in precedence order.
  final List<String> headers;

  /// Optional platform-specific connecting-IP header.
  final String? platformHeader;

  bool equivalentTo(AuthProxyPolicy other) {
    return trustsForwardedHeaders == other.trustsForwardedHeaders &&
        forwardClientIp == other.forwardClientIp &&
        _sameValues(proxies, other.proxies) &&
        _sameValues(headers, other.headers) &&
        platformHeader == other.platformHeader;
  }
}

/// Browser and network boundary required by production auth options.
final class AuthProductionBoundary {
  AuthProductionBoundary({
    required Iterable<Uri> trustedOrigins,
    required this.proxyPolicy,
  }) : trustedOrigins = List<String>.unmodifiable(
         trustedOrigins.map(_normalizeProductionOrigin).toSet(),
       ) {
    if (this.trustedOrigins.isEmpty) {
      throw ArgumentError.value(
        this.trustedOrigins,
        'trustedOrigins',
        'must contain at least one HTTPS application origin',
      );
    }
  }

  /// Exact HTTPS origins allowed to invoke browser-facing auth operations.
  final List<String> trustedOrigins;

  /// Explicit direct-connection or trusted-proxy decision.
  final AuthProxyPolicy proxyPolicy;
}

String normalizeAuthOrigin(Uri origin, {required bool requireHttps}) {
  final scheme = origin.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') ||
      (requireHttps && scheme != 'https') ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.query.isNotEmpty ||
      origin.fragment.isNotEmpty ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    throw ArgumentError.value(
      origin,
      'trustedOrigins',
      requireHttps
          ? 'must be an HTTPS origin without credentials, path, query, or fragment'
          : 'must be an HTTP origin without credentials, path, query, or fragment',
    );
  }
  final defaultPort = scheme == 'https' ? 443 : 80;
  final port = origin.hasPort && origin.port != defaultPort
      ? ':${origin.port}'
      : '';
  final normalizedHost = origin.host.contains(':')
      ? '[${origin.host.toLowerCase()}]'
      : origin.host.toLowerCase();
  return '$scheme://$normalizedHost$port';
}

String _normalizeProductionOrigin(Uri origin) =>
    normalizeAuthOrigin(origin, requireHttps: true);

String _normalizeProxyNetwork(String value) {
  final normalized = value.trim();
  final parts = normalized.split('/');
  if (parts.length > 2 || parts.first.isEmpty) {
    throw ArgumentError.value(
      value,
      'proxies',
      'must contain valid IP addresses or CIDR networks',
    );
  }
  final address = InternetAddress.tryParse(parts.first);
  if (address == null) {
    throw ArgumentError.value(
      value,
      'proxies',
      'must contain valid IP addresses or CIDR networks',
    );
  }
  if (parts.length == 1) return address.address;
  final prefix = int.tryParse(parts.last);
  final maximumPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
  if (prefix == null || prefix <= 0 || prefix > maximumPrefix) {
    throw ArgumentError.value(
      value,
      'proxies',
      'CIDR prefixes must be between 1 and $maximumPrefix',
    );
  }
  return '${address.address}/$prefix';
}

String _normalizeHeaderName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'headers',
      'must contain valid HTTP header names',
    );
  }
  return normalized;
}

bool _sameValues(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
