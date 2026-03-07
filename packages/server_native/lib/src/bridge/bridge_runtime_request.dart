part of 'bridge_runtime.dart';

/// `HttpRequest` adapter backed by a bridge request source and body stream.
final class BridgeHttpRequest extends Stream<Uint8List> implements HttpRequest {
  factory BridgeHttpRequest({
    required BridgeRequestFrame frame,
    required HttpResponse response,
    required Stream<Uint8List> bodyStream,
    HttpSession Function()? sessionFactory,
    bool stripTransferEncoding = false,
    BridgeConnectionInfo Function()? connectionInfoFactory,
  }) {
    final source = _BridgeFrameRequestSource(frame);
    final metadata = _bridgeRequestMetadataFromSource(source);
    return BridgeHttpRequest._fromSource(
      source: source,
      metadata: metadata,
      response: response,
      bodyStream: bodyStream,
      sessionFactory: sessionFactory,
      stripTransferEncoding: stripTransferEncoding,
      connectionInfoFactory:
          connectionInfoFactory ??
          () => _bridgeConnectionInfoFromSource(source, metadata: metadata),
    );
  }

  BridgeHttpRequest._fromSource({
    required _BridgeRequestSource source,
    required _BridgeRequestMetadata metadata,
    required this.response,
    required Stream<Uint8List> bodyStream,
    HttpSession Function()? sessionFactory,
    bool stripTransferEncoding = false,
    BridgeConnectionInfo Function()? connectionInfoFactory,
  }) : method = source.method,
       protocolVersion = source.protocol,
       persistentConnection = metadata.persistentConnection,
       _bodyStream = bodyStream,
       _source = source,
       _metadata = metadata,
       _sessionFactory = sessionFactory,
       _stripTransferEncoding = stripTransferEncoding,
       _connectionInfoFactory =
           connectionInfoFactory ??
           (() => _bridgeConnectionInfoFromSource(source, metadata: metadata)) {
    response.persistentConnection = persistentConnection;
  }

  _BridgeRequestHeaders? _headers;
  final _BridgeRequestSource _source;
  final _BridgeRequestMetadata _metadata;
  List<Cookie>? _cookies;
  final Stream<Uint8List> _bodyStream;
  HttpSession? _session;
  HttpSession Function()? _sessionFactory;
  final bool _stripTransferEncoding;
  final BridgeConnectionInfo Function() _connectionInfoFactory;
  BridgeConnectionInfo? _connectionInfo;

  @override
  final String method;

  @override
  final String protocolVersion;

  @override
  Uri get requestedUri =>
      _requestedUri ??= _buildBridgeRequestUri(_source, metadata: _metadata);
  Uri? _requestedUri;

  @override
  Uri get uri => requestedUri;

  @override
  HttpHeaders get headers => _headers ??= _buildBridgeRequestHeaders(
    _source,
    metadata: _metadata,
    stripTransferEncoding: _stripTransferEncoding,
  );

  @override
  int get contentLength {
    final headers = _headers;
    if (headers != null) {
      return headers.contentLength;
    }
    return _metadata.contentLength;
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
  HttpConnectionInfo? get connectionInfo =>
      _connectionInfo ??= _connectionInfoFactory();

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
