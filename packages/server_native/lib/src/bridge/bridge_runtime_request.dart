part of 'bridge_runtime.dart';

/// `HttpRequest` adapter backed by a bridge request source and body stream.
final class BridgeHttpRequest extends Stream<Uint8List> implements HttpRequest {
  BridgeHttpRequest({
    required BridgeRequestFrame frame,
    required HttpResponse response,
    required Stream<Uint8List> bodyStream,
    HttpSession Function()? sessionFactory,
    bool stripTransferEncoding = false,
    BridgeConnectionInfo? connectionInfo,
  }) : this._fromSource(
         source: _BridgeFrameRequestSource(frame),
         response: response,
         bodyStream: bodyStream,
         sessionFactory: sessionFactory,
         stripTransferEncoding: stripTransferEncoding,
         connectionInfo:
             connectionInfo ?? BridgeConnectionInfo.fromRequestFrame(frame),
       );

  BridgeHttpRequest._fromSource({
    required _BridgeRequestSource source,
    required this.response,
    required Stream<Uint8List> bodyStream,
    HttpSession Function()? sessionFactory,
    bool stripTransferEncoding = false,
    BridgeConnectionInfo? connectionInfo,
  }) : method = source.method,
       protocolVersion = source.protocol,
       persistentConnection = _derivePersistentConnection(source),
       _bodyStream = bodyStream,
       _source = source,
       _sessionFactory = sessionFactory,
       _stripTransferEncoding = stripTransferEncoding,
       _connectionInfo =
           connectionInfo ?? _bridgeConnectionInfoFromSource(source) {
    response.persistentConnection = persistentConnection;
  }

  _BridgeRequestHeaders? _headers;
  final _BridgeRequestSource _source;
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
  Uri get requestedUri => _requestedUri ??= _buildBridgeRequestUri(_source);
  Uri? _requestedUri;

  @override
  Uri get uri => requestedUri;

  @override
  HttpHeaders get headers => _headers ??= _buildBridgeRequestHeaders(
    _source,
    stripTransferEncoding: _stripTransferEncoding,
  );

  @override
  int get contentLength {
    final headers = _headers;
    if (headers != null) {
      return headers.contentLength;
    }
    final raw = _source.firstHeaderValue(HttpHeaders.contentLengthHeader);
    return raw == null ? -1 : int.tryParse(raw.trim()) ?? -1;
  }

  @override
  List<Cookie> get cookies {
    final existing = _cookies;
    if (existing != null) {
      return existing;
    }

    final parsed = <Cookie>[];
    _source.forEachHeader((name, value) {
      if (!_equalsAsciiIgnoreCase(name, HttpHeaders.cookieHeader)) {
        return;
      }
      for (final part in value.split(';')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) {
          continue;
        }
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
    });
    _cookies = parsed;
    return parsed;
  }

  @override
  final bool persistentConnection;

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

bool _derivePersistentConnection(_BridgeRequestSource source) {
  final protocol = source.protocol.trim().toLowerCase();
  var defaultPersistentConnection = true;
  if (protocol == '1.0' || protocol == 'http/1.0') {
    defaultPersistentConnection = false;
  }

  var hasClose = false;
  var hasKeepAlive = false;
  source.forEachHeader((name, value) {
    if (!_equalsAsciiIgnoreCase(name, HttpHeaders.connectionHeader)) {
      return;
    }
    for (final part in value.split(',')) {
      final token = _asciiLower(part.trim());
      if (token.isEmpty) {
        continue;
      }
      if (token == 'close') {
        hasClose = true;
      } else if (token == 'keep-alive') {
        hasKeepAlive = true;
      }
    }
  });

  if (hasClose) {
    return false;
  }
  if (hasKeepAlive) {
    return true;
  }
  return defaultPersistentConnection;
}
