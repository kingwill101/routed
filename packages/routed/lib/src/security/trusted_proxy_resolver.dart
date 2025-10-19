import 'dart:io';

import 'package:routed/src/security/network.dart';

class TrustedProxyResolver {
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
