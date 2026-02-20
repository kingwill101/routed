part of 'bridge_runtime.dart';

/// Buffered `HttpResponse` adapter for single-frame bridge responses.
final class BridgeHttpResponse implements HttpResponse {
  BridgeHttpResponse();

  _BridgeHttpHeaders? _headers;
  List<Cookie>? _cookies;
  final BytesBuilder _body = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  BridgeDetachedSocket? _detachedSocket;
  bool _detachedWriteHeaders = true;
  bool _closed = false;
  Encoding _encoding = utf8;
  bool _autoCompressEnabled = false;
  bool _requestAcceptsGzip = false;

  /// Enables gzip auto-compression based on request/response negotiation.
  void configureAutoCompression({
    required bool enabled,
    required bool requestAcceptsGzip,
  }) {
    _autoCompressEnabled = enabled;
    _requestAcceptsGzip = requestAcceptsGzip;
  }

  /// Returns buffered response bytes, optionally gzip-encoded.
  Uint8List takeBodyBytes() {
    if (_detachedSocket != null) {
      return Uint8List(0);
    }
    final bodyBytes = _body.takeBytes();
    if (!_shouldCompressBody(bodyBytes)) {
      return bodyBytes;
    }
    final compressed = Uint8List.fromList(gzip.encode(bodyBytes));
    headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    headers.contentLength = compressed.length;
    return compressed;
  }

  /// Detaches and returns the tunnel socket, if one was created.
  BridgeDetachedSocket? takeDetachedSocket() {
    final detached = _detachedSocket;
    _detachedSocket = null;
    return detached;
  }

  @override
  int statusCode = HttpStatus.ok;

  @override
  String reasonPhrase = 'OK';

  @override
  bool persistentConnection = true;

  @override
  Duration? deadline;

  @override
  bool bufferOutput = true;

  @override
  HttpHeaders get headers => _headers ??= _BridgeHttpHeaders();

  @override
  List<Cookie> get cookies => _cookies ??= <Cookie>[];

  @override
  int get contentLength => _headers?.contentLength ?? -1;

  @override
  set contentLength(int value) => headers.contentLength = value;

  @override
  HttpConnectionInfo? get connectionInfo => const BridgeConnectionInfo();

  @override
  void add(List<int> data) {
    _ensureOpen();
    _body.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    _ensureOpen();
    await for (final chunk in stream) {
      _body.add(chunk);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding value) => _encoding = value;

  @override
  void write(Object? object) => add(encoding.encode(object?.toString() ?? ''));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  Future<void> flush() async {}

  @override
  Future<void> redirect(
    Uri location, {
    int status = HttpStatus.movedTemporarily,
  }) async {
    headers.set(HttpHeaders.locationHeader, location.toString());
    statusCode = status;
    await close();
  }

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) async {
    _ensureOpen();
    if (_detachedSocket != null) {
      throw StateError('Response socket has already been detached');
    }
    _detachedWriteHeaders = writeHeaders;
    final detached = await _createDetachedSocketPair();
    _detachedSocket = detached;
    _closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
    return detached.applicationSocket;
  }

  /// Parses and applies manually-written detached response headers.
  ///
  /// When callers use `detachSocket(writeHeaders: false)` they may write a raw
  /// HTTP status/header preface directly to the detached socket. We parse that
  /// preface so the bridge still emits a proper structured response start.
  Future<void> prepareDetachedHeaders() async {
    final detached = _detachedSocket;
    if (detached == null || _detachedWriteHeaders) {
      return;
    }
    final preface = await _readDetachedHttpResponsePreface(detached);
    detached.stashPrefetchedTunnelBytes(preface.trailingBytes);

    statusCode = preface.status;
    final bridgeHeaders = headers;
    bridgeHeaders.clear();
    for (var i = 0; i < preface.headerNames.length; i++) {
      bridgeHeaders.add(preface.headerNames[i], preface.headerValues[i]);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Response is already closed');
    }
  }

  bool _shouldCompressBody(Uint8List bodyBytes) {
    if (!_autoCompressEnabled || !_requestAcceptsGzip || bodyBytes.isEmpty) {
      return false;
    }
    final contentEncoding = _headers?.value(HttpHeaders.contentEncodingHeader);
    if (contentEncoding != null && contentEncoding.isNotEmpty) {
      return false;
    }
    return true;
  }

  void appendFlattenedHeaders(
    List<String> headerNames,
    List<String> headerValues,
  ) {
    final originalLength = headerNames.length;
    final total = flattenedHeaderCount;
    if (total == 0) {
      return;
    }
    headerNames.length = originalLength + total;
    headerValues.length = originalLength + total;
    _writeFlattenedHeaders(headerNames, headerValues, originalLength);
  }

  int get flattenedHeaderCount {
    final headerCount = _headers?.flattenedHeaderValueCount ?? 0;
    final cookieCount = _cookies?.length ?? 0;
    return headerCount + cookieCount;
  }

  void writeFlattenedHeaders(
    List<String> headerNames,
    List<String> headerValues,
  ) {
    _writeFlattenedHeaders(headerNames, headerValues, 0);
  }

  void _writeFlattenedHeaders(
    List<String> headerNames,
    List<String> headerValues,
    int offset,
  ) {
    final headers = _headers;
    if (headers != null) {
      offset = headers.writeFlattenedHeaderPairs(
        headerNames,
        headerValues,
        offset,
      );
    }
    final cookies = _cookies;
    if (cookies != null) {
      for (final cookie in cookies) {
        headerNames[offset] = HttpHeaders.setCookieHeader;
        headerValues[offset] = cookie.toString();
        offset++;
      }
    }
  }
}
