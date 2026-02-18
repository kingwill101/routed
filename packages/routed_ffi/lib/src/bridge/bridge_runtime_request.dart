part of 'bridge_runtime.dart';

/// `HttpRequest` adapter backed by a [BridgeRequestFrame] and body stream.
final class BridgeHttpRequest extends Stream<Uint8List> implements HttpRequest {
  BridgeHttpRequest({
    required BridgeRequestFrame frame,
    required this.response,
    required Stream<Uint8List> bodyStream,
  }) : method = frame.method,
       protocolVersion = frame.protocol,
       requestedUri = _buildUri(frame),
       _bodyStream = bodyStream,
       _frame = frame;

  static Uri _buildUri(BridgeRequestFrame frame) {
    final authority = _splitAuthority(frame.authority);
    return Uri(
      scheme: frame.scheme.isEmpty ? 'http' : frame.scheme,
      host: authority.host.isEmpty ? '127.0.0.1' : authority.host,
      port: authority.port,
      path: frame.path.isEmpty ? '/' : frame.path,
      query: frame.query.isEmpty ? null : frame.query,
    );
  }

  static Http2Headers _buildHeaders(BridgeRequestFrame frame) {
    final headers = Http2Headers();
    for (var i = 0; i < frame.headerCount; i++) {
      headers.add(frame.headerNameAt(i), frame.headerValueAt(i));
    }
    return headers;
  }

  Http2Headers? _headers;
  final BridgeRequestFrame _frame;
  List<Cookie>? _cookies;
  final Stream<Uint8List> _bodyStream;

  @override
  final String method;

  @override
  final String protocolVersion;

  @override
  final Uri requestedUri;

  @override
  Uri get uri => requestedUri;

  @override
  HttpHeaders get headers => _headers ??= _buildHeaders(_frame);

  @override
  int get contentLength {
    final headers = _headers;
    if (headers != null) {
      return headers.contentLength;
    }
    for (var i = 0; i < _frame.headerCount; i++) {
      final name = _frame.headerNameAt(i);
      if (_equalsAsciiIgnoreCase(name, HttpHeaders.contentLengthHeader)) {
        return int.tryParse(_frame.headerValueAt(i).trim()) ?? -1;
      }
    }
    return -1;
  }

  @override
  List<Cookie> get cookies {
    final existing = _cookies;
    if (existing != null) {
      return existing;
    }

    final parsed = <Cookie>[];
    for (var i = 0; i < _frame.headerCount; i++) {
      final name = _frame.headerNameAt(i);
      if (!_equalsAsciiIgnoreCase(name, HttpHeaders.cookieHeader)) {
        continue;
      }
      for (final part in _frame.headerValueAt(i).split(';')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final idx = trimmed.indexOf('=');
        if (idx == -1) {
          parsed.add(Cookie(trimmed, ''));
        } else {
          parsed.add(
            Cookie(
              trimmed.substring(0, idx).trim(),
              trimmed.substring(idx + 1).trim(),
            ),
          );
        }
      }
    }
    _cookies = parsed;
    return parsed;
  }

  @override
  bool persistentConnection = true;

  @override
  X509Certificate? get certificate => null;

  @override
  HttpSession get session => _session ??= BridgeSession();
  BridgeSession? _session;

  @override
  HttpConnectionInfo? get connectionInfo => const BridgeConnectionInfo();

  @override
  final HttpResponse response;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _bodyStream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<Socket> detachSocket({bool writeHeaders = true}) {
    return response.detachSocket(writeHeaders: writeHeaders);
  }

  Future<HttpClientResponse> upgrade(Future<void> Function(Socket p1) handler) {
    throw UnsupportedError('upgrade is not supported by bridge requests');
  }
}

/// Parsed authority (`host[:port]`) value used by bridge request adapters.
final class ParsedAuthority {
  const ParsedAuthority({required this.host, required this.port});

  final String host;
  final int? port;
}

ParsedAuthority _splitAuthority(String authority) {
  if (authority.isEmpty) {
    return const ParsedAuthority(host: '127.0.0.1', port: null);
  }

  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end > 0) {
      final host = authority.substring(1, end);
      final suffix = authority.substring(end + 1);
      if (suffix.startsWith(':')) {
        final parsedPort = int.tryParse(suffix.substring(1));
        if (parsedPort != null) {
          return ParsedAuthority(host: host, port: parsedPort);
        }
      }
      return ParsedAuthority(host: host, port: null);
    }
  }

  final firstColon = authority.indexOf(':');
  final lastColon = authority.lastIndexOf(':');
  if (firstColon != -1 && firstColon == lastColon) {
    final host = authority.substring(0, firstColon);
    final parsedPort = int.tryParse(authority.substring(firstColon + 1));
    if (parsedPort != null) {
      return ParsedAuthority(host: host, port: parsedPort);
    }
  }

  return ParsedAuthority(host: authority, port: null);
}

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
