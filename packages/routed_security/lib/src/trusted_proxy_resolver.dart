import 'dart:io';

import 'package:routed/src/security/network.dart';

/// A resolver that determines the client IP address, considering trusted proxies
/// and headers. This is useful for applications deployed behind reverse proxies.
class TrustedProxyResolver {
  /// Creates a [TrustedProxyResolver].
  ///
  /// - [enabled]: Whether the resolver is active.
  /// - [forwardClientIp]: Whether to forward the client IP from headers.
  /// - [proxies]: A list of trusted proxy IPs or CIDR ranges.
  /// - [headers]: A list of headers to check for forwarded client IPs.
  /// - [trustedPlatform]: A specific platform header to trust, if any.
  ///
  /// Example:
  /// ```dart
  /// final resolver = TrustedProxyResolver(
  ///   enabled: true,
  ///   forwardClientIp: true,
  ///   proxies: ['192.168.1.1', '10.0.0.0/8'],
  ///   headers: ['x-forwarded-for'],
  ///   trustedPlatform: 'x-custom-platform',
  /// );
  /// ```
  TrustedProxyResolver({
    required bool enabled,
    required bool forwardClientIp,
    required List<String> proxies,
    required List<String> headers,
    String? trustedPlatform,
  }) : _enabled = enabled,
       _forwardClientIp = forwardClientIp,
       _trustedPlatform = trustedPlatform,
       _headers = headers
           .map((header) => header.trim())
           .where((h) => h.isNotEmpty)
           .toList(),
       _networks = proxies
           .map(NetworkMatcher.maybeParse)
           .whereType<NetworkMatcher>()
           .toList();

  bool _enabled;
  bool _forwardClientIp;
  String? _trustedPlatform;
  final List<String> _headers;
  List<NetworkMatcher> _networks;

  /// Updates the resolver's configuration.
  ///
  /// - [enabled]: Updates whether the resolver is active.
  /// - [forwardClientIp]: Updates whether to forward the client IP.
  /// - [trustedPlatform]: Updates the trusted platform header.
  /// - [proxies]: Updates the list of trusted proxies.
  /// - [headers]: Updates the list of headers to check.
  ///
  /// Example:
  /// ```dart
  /// resolver.update(
  ///   enabled: false,
  ///   proxies: ['127.0.0.1'],
  ///   headers: ['x-real-ip'],
  /// );
  /// ```
  void update({
    bool? enabled,
    bool? forwardClientIp,
    String? trustedPlatform,
    List<String>? proxies,
    List<String>? headers,
  }) {
    if (enabled != null) _enabled = enabled;
    if (forwardClientIp != null) _forwardClientIp = forwardClientIp;
    if (trustedPlatform != null) {
      _trustedPlatform = trustedPlatform.isEmpty ? null : trustedPlatform;
    }
    if (proxies != null) {
      _networks = proxies
          .map(NetworkMatcher.maybeParse)
          .whereType<NetworkMatcher>()
          .toList();
    }
    if (headers != null) {
      _headers
        ..clear()
        ..addAll(
          headers.map((header) => header.trim()).where((h) => h.isNotEmpty),
        );
    }
  }

  /// Resolves the client IP address from the [HttpRequest].
  ///
  /// - If the resolver is disabled or forwarding is disabled, returns the
  ///   remote address of the request.
  /// - If the remote address is not a trusted proxy, returns the remote address.
  /// - Otherwise, checks the trusted platform header and configured headers
  ///   for the forwarded client IP.
  ///
  /// Example:
  /// ```dart
  /// final clientIp = resolver.resolve(request);
  /// print('Client IP: $clientIp');
  /// ```
  String resolve(HttpRequest request) {
    final remoteAddr = _normalize(request.connectionInfo?.remoteAddress);
    if (!_enabled || !_forwardClientIp) {
      return remoteAddr?.address ?? '';
    }
    if (remoteAddr == null || !_isTrustedProxy(remoteAddr)) {
      return remoteAddr?.address ?? '';
    }

    if (_trustedPlatform != null) {
      final platformIp = request.headers[_trustedPlatform!]?.first;
      if (platformIp != null && platformIp.isNotEmpty) {
        return platformIp;
      }
    }

    for (final header in _headers) {
      final values = request.headers[header];
      if (values != null && values.isNotEmpty) {
        final forwarded = values.first.split(',').first.trim();
        if (forwarded.isNotEmpty) {
          return forwarded;
        }
      }
    }

    return remoteAddr.address;
  }

  /// Checks if the given [address] is a trusted proxy.
  ///
  /// - Returns `true` if the address matches any of the configured trusted
  ///   proxies or CIDR ranges.
  /// - Returns `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// final isTrusted = resolver._isTrustedProxy(InternetAddress('192.168.1.1'));
  /// print('Is trusted proxy: $isTrusted');
  /// ```
  bool _isTrustedProxy(InternetAddress address) {
    final normalized = _normalize(address);
    if (normalized == null || _networks.isEmpty) {
      return false;
    }
    final target = normalized;
    for (final network in _networks) {
      if (network.contains(target)) {
        return true;
      }
    }
    return false;
  }

  /// Normalizes an [InternetAddress].
  ///
  /// - Converts IPv6-mapped IPv4 addresses to their IPv4 equivalent.
  /// - Returns the original address if no normalization is needed.
  ///
  /// Example:
  /// ```dart
  /// final normalized = resolver._normalize(InternetAddress('::ffff:192.168.1.1'));
  /// print('Normalized address: ${normalized?.address}');
  /// ```
  InternetAddress? _normalize(InternetAddress? address) {
    if (address == null) {
      return null;
    }
    if (address.type != InternetAddressType.IPv6) {
      return address;
    }
    final raw = address.rawAddress;
    if (raw.length == 16) {
      final isMapped =
          raw[0] == 0 &&
          raw[1] == 0 &&
          raw[2] == 0 &&
          raw[3] == 0 &&
          raw[4] == 0 &&
          raw[5] == 0 &&
          raw[6] == 0 &&
          raw[7] == 0 &&
          raw[8] == 0 &&
          raw[9] == 0 &&
          raw[10] == 0xFF &&
          raw[11] == 0xFF;
      if (isMapped) {
        final v4Bytes = raw.sublist(12, 16);
        return InternetAddress.fromRawAddress(
          v4Bytes,
          type: InternetAddressType.IPv4,
        );
      }
    }
    return address;
  }
}
