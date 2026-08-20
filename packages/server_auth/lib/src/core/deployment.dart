import 'dart:io';

import 'account_deletion.dart';
import 'api_key.dart';
import 'auth_config.dart';
import 'email_change.dart';
import 'options.dart';
import 'password_reset.dart';

/// Explicit policy for forwarded client-address headers at an auth boundary.
///
/// Framework adapters remain responsible for applying this policy to their
/// HTTP server. Keeping it in the deployment bundle prevents production auth
/// configuration from silently assuming whether a request is direct or
/// passed through trusted infrastructure.
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
}

/// Browser and network boundary required by production auth presets.
final class AuthProductionBoundary {
  AuthProductionBoundary({
    required Iterable<Uri> trustedOrigins,
    required this.proxyPolicy,
  }) : trustedOrigins = List<String>.unmodifiable(
         trustedOrigins.map(_normalizeProductionOrigin),
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

/// Application-owned delivery behavior for account lifecycle operations.
///
/// Production presets require an explicit instance. Applications can either
/// provide all supported delivery callbacks or deliberately disable these
/// optional routes. No callback is synthesized and no raw token is logged.
final class AuthLifecycleDelivery<TContext> {
  /// Enables only the lifecycle delivery capabilities supplied by the app.
  ///
  /// Omitted callbacks leave their corresponding routes unavailable; presets
  /// never synthesize delivery or force unrelated lifecycle capabilities to
  /// be enabled together.
  const AuthLifecycleDelivery({
    this.passwordReset,
    this.emailChange,
    this.accountDeletion,
  });

  /// Explicitly disables every optional lifecycle delivery capability.
  const AuthLifecycleDelivery.disabled() : this();

  final AuthPasswordResetSender<TContext>? passwordReset;
  final AuthEmailChangeSender<TContext>? emailChange;
  final AuthAccountDeletionSender<TContext>? accountDeletion;

  bool get hasAny =>
      passwordReset != null || emailChange != null || accountDeletion != null;
}

/// A typed auth deployment assembled from framework-neutral runtime options.
///
/// The bundle remains inspectable: callers bind [options] to their runtime,
/// pass [configuration] to their framework auth provider, and apply
/// [proxyPolicy] to the HTTP server or security provider.
class AuthDeployment<TContext> {
  /// Creates an advanced custom bundle without applying a preset.
  const AuthDeployment.custom({
    required this.options,
    required this.configuration,
    required this.proxyPolicy,
  });

  final AuthOptions<TContext> options;
  final AuthConfig configuration;
  final AuthProxyPolicy proxyPolicy;

  bool get requiresDurableStore => options.storeMode == AuthStoreMode.durable;
}

/// Service deployment that retains its API-key plugin for middleware wiring.
final class AuthApiKeyDeployment<TContext> extends AuthDeployment<TContext> {
  /// Creates an advanced custom API-key bundle without applying a preset.
  const AuthApiKeyDeployment.custom({
    required super.options,
    required super.configuration,
    required super.proxyPolicy,
    required this.apiKeys,
  }) : super.custom();

  final AuthApiKeyPlugin<TContext> apiKeys;
}

String _normalizeProductionOrigin(Uri origin) {
  if (origin.scheme.toLowerCase() != 'https') {
    throw ArgumentError.value(
      origin,
      'trustedOrigins',
      'production origins must use HTTPS',
    );
  }
  return _normalizeOrigin(origin);
}

String _normalizeOrigin(Uri origin) {
  final scheme = origin.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.query.isNotEmpty ||
      origin.fragment.isNotEmpty ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    throw ArgumentError.value(
      origin,
      'trustedOrigins',
      'must be an HTTP origin without credentials, path, query, or fragment',
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
