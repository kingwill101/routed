part of 'bridge_runtime.dart';

/// Parsed authority (`host[:port]`) value used by bridge request adapters.
final class _BridgeParsedAuthority {
  const _BridgeParsedAuthority({required this.host, required this.port});

  final String host;
  final int? port;
}

/// Builds `HttpRequest.requestedUri` from frame pseudo-headers and metadata.
Uri _buildBridgeRequestUri(BridgeRequestFrame frame) {
  final absolute = _tryAbsoluteRequestUri(frame);
  if (absolute != null) {
    return absolute;
  }

  final forwardedProto = _bridgeHeaderValue(frame, 'x-forwarded-proto')?.trim();
  final forwardedHost = _bridgeHeaderValue(frame, 'x-forwarded-host')?.trim();
  final hostHeader = _bridgeHeaderValue(frame, HttpHeaders.hostHeader)?.trim();
  final authorityValue = (forwardedHost?.isNotEmpty ?? false)
      ? forwardedHost!
      : (hostHeader?.isNotEmpty ?? false)
      ? hostHeader!
      : frame.authority;
  final authority = _splitBridgeAuthority(authorityValue);
  return Uri(
    scheme: (forwardedProto != null && forwardedProto.isNotEmpty)
        ? forwardedProto
        : frame.scheme.isEmpty
        ? 'http'
        : frame.scheme,
    host: authority.host.isEmpty ? '127.0.0.1' : authority.host,
    port: authority.port,
    path: frame.path.isEmpty ? '/' : frame.path,
    query: frame.query.isEmpty ? null : frame.query,
  );
}

/// Parses a `host[:port]` authority component.
_BridgeParsedAuthority _splitBridgeAuthority(String authority) {
  if (authority.isEmpty) {
    return const _BridgeParsedAuthority(host: '127.0.0.1', port: null);
  }

  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end > 0) {
      final host = authority.substring(1, end);
      final suffix = authority.substring(end + 1);
      if (suffix.startsWith(':')) {
        final parsedPort = int.tryParse(suffix.substring(1));
        if (parsedPort != null) {
          return _BridgeParsedAuthority(host: host, port: parsedPort);
        }
      }
      return _BridgeParsedAuthority(host: host, port: null);
    }
  }

  final firstColon = authority.indexOf(':');
  final lastColon = authority.lastIndexOf(':');
  if (firstColon != -1 && firstColon == lastColon) {
    final host = authority.substring(0, firstColon);
    final parsedPort = int.tryParse(authority.substring(firstColon + 1));
    if (parsedPort != null) {
      return _BridgeParsedAuthority(host: host, port: parsedPort);
    }
  }

  return _BridgeParsedAuthority(host: authority, port: null);
}

@pragma('vm:prefer-inline')
bool _equalsAsciiIgnoreCase(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    var x = a.codeUnitAt(i);
    var y = b.codeUnitAt(i);
    if (x == y) {
      continue;
    }
    if (x >= 0x41 && x <= 0x5a) {
      x += 0x20;
    }
    if (y >= 0x41 && y <= 0x5a) {
      y += 0x20;
    }
    if (x != y) {
      return false;
    }
  }
  return true;
}

/// Returns the first matching header value by case-insensitive [name].
String? _bridgeHeaderValue(BridgeRequestFrame frame, String name) {
  for (var i = 0; i < frame.headerCount; i++) {
    final headerName = frame.headerNameAt(i);
    if (_equalsAsciiIgnoreCase(headerName, name)) {
      return frame.headerValueAt(i);
    }
  }
  return null;
}

/// Attempts to parse an absolute request URI from the request path.
Uri? _tryAbsoluteRequestUri(BridgeRequestFrame frame) {
  final path = frame.path;
  if (!(path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('ws://') ||
      path.startsWith('wss://'))) {
    return null;
  }
  final uri = Uri.tryParse(path);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return null;
  }
  return uri;
}
