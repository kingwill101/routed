part of 'bridge_runtime.dart';

/// `HttpRequest` adapter backed by a [BridgeRequestFrame] and body stream.
final class BridgeHttpRequest extends Stream<Uint8List> implements HttpRequest {
  BridgeHttpRequest({
    required BridgeRequestFrame frame,
    required this.response,
    required Stream<Uint8List> bodyStream,
    HttpSession Function()? sessionFactory,
    bool stripTransferEncoding = false,
    BridgeConnectionInfo? connectionInfo,
  }) : method = frame.method,
       protocolVersion = frame.protocol,
       _bodyStream = bodyStream,
       _frame = frame,
       _sessionFactory = sessionFactory,
       _stripTransferEncoding = stripTransferEncoding,
       _connectionInfo =
           connectionInfo ?? BridgeConnectionInfo.fromRequestFrame(frame);

  _BridgeRequestHeaders? _headers;
  final BridgeRequestFrame _frame;
  List<Cookie>? _cookies;
  final Stream<Uint8List> _bodyStream;
  HttpSession? _session;
  HttpSession Function()? _sessionFactory;
  final bool _stripTransferEncoding;
  final BridgeConnectionInfo _connectionInfo;

  @override
  final String method;

  @override
  final String protocolVersion;

  @override
  Uri get requestedUri => _requestedUri ??= _buildBridgeRequestUri(_frame);
  Uri? _requestedUri;

  @override
  Uri get uri => requestedUri;

  @override
  HttpHeaders get headers => _headers ??= _buildBridgeRequestHeaders(
    _frame,
    stripTransferEncoding: _stripTransferEncoding,
  );

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

  /// Installs a lazy [HttpSession] factory for this request.
  void setSessionFactory(HttpSession Function() sessionFactory) {
    _sessionFactory = sessionFactory;
  }

  @override
  HttpConnectionInfo? get connectionInfo => _connectionInfo;

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
