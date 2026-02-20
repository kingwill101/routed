part of 'bridge_runtime.dart';

/// Streaming `HttpResponse` adapter for chunked bridge responses.
final class BridgeStreamingHttpResponse implements HttpResponse {
  BridgeStreamingHttpResponse({required this.onStart, required this.onChunk});

  final Future<void> Function(BridgeResponseFrame frame) onStart;
  final Future<void> Function(Uint8List chunkBytes) onChunk;

  _BridgeHttpHeaders? _headers;
  List<Cookie>? _cookies;
  final Completer<void> _done = Completer<void>();
  BridgeDetachedSocket? _detachedSocket;
  Future<void> _pendingWrite = Future<void>.value();
  bool _closed = false;
  bool _started = false;
  Encoding _encoding = utf8;
  bool _autoCompressEnabled = false;
  bool _requestAcceptsGzip = false;
  bool _compressBody = false;
  BytesBuilder? _compressionBuffer;

  bool get isClosed => _closed;

  /// Enables gzip auto-compression based on request/response negotiation.
  void configureAutoCompression({
    required bool enabled,
    required bool requestAcceptsGzip,
  }) {
    _autoCompressEnabled = enabled;
    _requestAcceptsGzip = requestAcceptsGzip;
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
    if (data.isEmpty) {
      return;
    }
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    _enqueueWrite(() async {
      await _ensureStarted();
      if (_compressBody) {
        (_compressionBuffer ??= BytesBuilder(copy: false)).add(chunk);
        return;
      }
      await onChunk(chunk);
    });
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    _ensureOpen();
    await for (final chunk in stream) {
      add(chunk);
    }
    await _pendingWrite;
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
    _enqueueWrite(() async {
      await _ensureStarted();
      if (_compressBody) {
        final buffered = _compressionBuffer?.takeBytes() ?? Uint8List(0);
        if (buffered.isNotEmpty) {
          await onChunk(Uint8List.fromList(gzip.encode(buffered)));
        }
      }
    });
    await _pendingWrite;
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
  Future<void> flush() async => _pendingWrite;

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
    final detached = await _createDetachedSocketPair();
    _detachedSocket = detached;
    await _ensureStarted();
    _closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
    return detached.applicationSocket;
  }

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    _started = true;
    _compressBody = _shouldCompressBody();
    if (_compressBody) {
      final compressionHeaders = headers;
      compressionHeaders.set(HttpHeaders.contentEncodingHeader, 'gzip');
      compressionHeaders.contentLength = -1;
    }

    final bridgeHeaders = _headers;
    final cookies = _cookies;
    final headerCount =
        (bridgeHeaders?.flattenedHeaderValueCount ?? 0) +
        (cookies?.length ?? 0);
    final headerNames = headerCount == 0
        ? const <String>[]
        : List<String>.filled(headerCount, '', growable: false);
    final headerValues = headerCount == 0
        ? const <String>[]
        : List<String>.filled(headerCount, '', growable: false);

    if (headerCount != 0) {
      var offset = 0;
      if (bridgeHeaders != null) {
        offset = bridgeHeaders.writeFlattenedHeaderPairs(
          headerNames,
          headerValues,
          offset,
        );
      }
      if (cookies != null) {
        for (final cookie in cookies) {
          headerNames[offset] = HttpHeaders.setCookieHeader;
          headerValues[offset] = cookie.toString();
          offset++;
        }
      }
    }

    await onStart(
      BridgeResponseFrame.fromHeaderPairs(
        status: statusCode,
        headerNames: headerNames,
        headerValues: headerValues,
        bodyBytes: Uint8List(0),
        detachedSocket: _detachedSocket,
      ),
    );
  }

  void _enqueueWrite(Future<void> Function() action) {
    _pendingWrite = _pendingWrite.then((_) => action()).catchError((
      error,
      stack,
    ) {
      if (!_done.isCompleted) {
        _done.completeError(error, stack);
      }
    });
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Response is already closed');
    }
  }

  bool _shouldCompressBody() {
    if (!_autoCompressEnabled || !_requestAcceptsGzip) {
      return false;
    }
    final contentEncoding = _headers?.value(HttpHeaders.contentEncodingHeader);
    if (contentEncoding != null && contentEncoding.isNotEmpty) {
      return false;
    }
    return true;
  }
}
