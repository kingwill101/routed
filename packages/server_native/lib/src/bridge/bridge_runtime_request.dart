part of 'bridge_runtime.dart';

/// `HttpRequest` adapter backed by a [BridgeRequestFrame] and body stream.
final class BridgeHttpRequest extends Stream<Uint8List> implements HttpRequest {
  BridgeHttpRequest({
    required BridgeRequestFrame frame,
    required this.response,
    required Stream<Uint8List> bodyStream,
    HttpSession Function()? sessionFactory,
  }) : method = frame.method,
       protocolVersion = frame.protocol,
       _bodyStream = bodyStream,
       _frame = frame,
       _sessionFactory = sessionFactory;

  static Uri _buildUri(BridgeRequestFrame frame) {
    final absolute = _tryAbsoluteRequestUri(frame);
    if (absolute != null) {
      return absolute;
    }

    final forwardedProto = _headerValue(frame, 'x-forwarded-proto')?.trim();
    final forwardedHost = _headerValue(frame, 'x-forwarded-host')?.trim();
    final hostHeader = _headerValue(frame, HttpHeaders.hostHeader)?.trim();
    final authorityValue = (forwardedHost?.isNotEmpty ?? false)
        ? forwardedHost!
        : (hostHeader?.isNotEmpty ?? false)
        ? hostHeader!
        : frame.authority;
    final authority = _splitAuthority(authorityValue);
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

  static _BridgeRequestHeaders _buildHeaders(BridgeRequestFrame frame) {
    return _BridgeRequestHeaders.fromFrame(frame);
  }

  _BridgeRequestHeaders? _headers;
  final BridgeRequestFrame _frame;
  List<Cookie>? _cookies;
  final Stream<Uint8List> _bodyStream;
  HttpSession? _session;
  HttpSession Function()? _sessionFactory;

  @override
  final String method;

  @override
  final String protocolVersion;

  @override
  Uri get requestedUri => _requestedUri ??= _buildUri(_frame);
  Uri? _requestedUri;

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
  HttpSession get session {
    final existing = _session;
    if (existing != null) {
      return existing;
    }
    final sessionFactory = _sessionFactory;
    if (sessionFactory != null) {
      final next = sessionFactory();
      _session = next;
      return next;
    }
    return _session ??= BridgeSession();
  }

  void setSessionFactory(HttpSession Function() sessionFactory) {
    _sessionFactory = sessionFactory;
  }

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

/// Immutable request-headers implementation backed by bridge frame data.
final class _BridgeRequestHeaders implements HttpHeaders {
  _BridgeRequestHeaders.fromFrame(BridgeRequestFrame frame) {
    for (var i = 0; i < frame.headerCount; i++) {
      final name = frame.headerNameAt(i);
      final normalized = _asciiLower(name);
      final values = _headers.putIfAbsent(normalized, () => <String>[]);
      values.add(frame.headerValueAt(i));
      _originalNames[normalized] = name;
    }
  }

  final Map<String, List<String>> _headers = <String, List<String>>{};
  final Map<String, String> _originalNames = <String, String>{};

  @override
  DateTime? get date => _parseDate(HttpHeaders.dateHeader);

  @override
  set date(DateTime? value) => _immutable();

  @override
  DateTime? get expires => _parseDate(HttpHeaders.expiresHeader);

  @override
  set expires(DateTime? value) => _immutable();

  @override
  DateTime? get ifModifiedSince =>
      _parseDate(HttpHeaders.ifModifiedSinceHeader);

  @override
  set ifModifiedSince(DateTime? value) => _immutable();

  @override
  String? get host {
    final parsed = _parseHostPort();
    return parsed?.host;
  }

  @override
  set host(String? value) => _immutable();

  @override
  int? get port {
    final parsed = _parseHostPort();
    return parsed?.port;
  }

  @override
  set port(int? value) => _immutable();

  @override
  ContentType? get contentType {
    final raw = value(HttpHeaders.contentTypeHeader);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return ContentType.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  set contentType(ContentType? value) => _immutable();

  @override
  int get contentLength {
    final raw = value(HttpHeaders.contentLengthHeader);
    if (raw == null || raw.isEmpty) {
      return -1;
    }
    return int.tryParse(raw.trim()) ?? -1;
  }

  @override
  set contentLength(int value) => _immutable();

  @override
  bool get persistentConnection {
    final values = _headers[_asciiLower(HttpHeaders.connectionHeader)];
    if (values == null || values.isEmpty) {
      return true;
    }
    if (_containsTokenIgnoreCase(values, 'close')) {
      return false;
    }
    if (_containsTokenIgnoreCase(values, 'keep-alive')) {
      return true;
    }
    return true;
  }

  @override
  set persistentConnection(bool value) => _immutable();

  @override
  bool get chunkedTransferEncoding {
    final values = _headers[_asciiLower(HttpHeaders.transferEncodingHeader)];
    if (values == null || values.isEmpty) {
      return false;
    }
    return _containsTokenIgnoreCase(values, 'chunked');
  }

  @override
  set chunkedTransferEncoding(bool value) => _immutable();

  @override
  List<String>? operator [](String name) {
    final values = _headers[_asciiLower(name)];
    return values == null ? null : List<String>.of(values);
  }

  @override
  String? value(String name) {
    final values = _headers[_asciiLower(name)];
    if (values == null || values.isEmpty) {
      return null;
    }
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _immutable();

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _immutable();

  @override
  void remove(String name, Object value) => _immutable();

  @override
  void removeAll(String name) => _immutable();

  @override
  void forEach(void Function(String name, List<String> values) action) {
    for (final entry in _headers.entries) {
      action(
        _originalNames[entry.key] ?? entry.key,
        List<String>.of(entry.value),
      );
    }
  }

  @override
  void noFolding(String name) => _immutable();

  @override
  void clear() => _immutable();

  Never _immutable() {
    throw UnsupportedError('Request headers are immutable');
  }

  DateTime? _parseDate(String name) {
    final raw = value(name);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return null;
    }
  }

  ParsedAuthority? _parseHostPort() {
    final raw = value(HttpHeaders.hostHeader);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _splitAuthority(raw);
  }

  bool _containsTokenIgnoreCase(List<String> values, String token) {
    final target = _asciiLower(token);
    for (final value in values) {
      for (final part in value.split(',')) {
        if (_asciiLower(part.trim()) == target) {
          return true;
        }
      }
    }
    return false;
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

String? _headerValue(BridgeRequestFrame frame, String name) {
  for (var i = 0; i < frame.headerCount; i++) {
    final headerName = frame.headerNameAt(i);
    if (_equalsAsciiIgnoreCase(headerName, name)) {
      return frame.headerValueAt(i);
    }
  }
  return null;
}

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
