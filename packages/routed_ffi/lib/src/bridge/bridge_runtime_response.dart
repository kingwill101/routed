part of 'bridge_runtime.dart';

/// Socket pair used to bridge upgraded protocol bytes over FFI frames.
final class BridgeDetachedSocket {
  BridgeDetachedSocket({
    required this.applicationSocket,
    required this.bridgeSocket,
  });

  /// Socket handed to Dart upgrade APIs (`WebSocketTransformer.upgrade`).
  final Socket applicationSocket;

  /// Peer socket retained by the bridge runtime for Rust tunnel forwarding.
  final Socket bridgeSocket;

  Future<void> close() async {
    try {
      await applicationSocket.close();
    } catch (_) {}
    try {
      await bridgeSocket.close();
    } catch (_) {}
  }
}

/// Buffered `HttpResponse` adapter for single-frame bridge responses.
final class BridgeHttpResponse implements HttpResponse {
  BridgeHttpResponse();

  Http2Headers? _headers;
  List<Cookie>? _cookies;
  final BytesBuilder _body = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  BridgeDetachedSocket? _detachedSocket;
  bool _closed = false;
  Encoding _encoding = utf8;

  Uint8List takeBodyBytes() => _detachedSocket == null
      ? _body.takeBytes()
      : Uint8List(0);

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
  HttpHeaders get headers => _headers ??= Http2Headers();

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
    final detached = await _createDetachedSocketPair();
    _detachedSocket = detached;
    _closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
    return detached.applicationSocket;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Response is already closed');
    }
  }

  void appendFlattenedHeaders(
    List<String> headerNames,
    List<String> headerValues,
  ) {
    final headers = _headers;
    if (headers == null) {
      return;
    }
    headers.forEach((name, values) {
      for (final value in values) {
        headerNames.add(name);
        headerValues.add(value);
      }
    });
  }
}

/// Streaming `HttpResponse` adapter for chunked bridge responses.
final class BridgeStreamingHttpResponse implements HttpResponse {
  BridgeStreamingHttpResponse({required this.onStart, required this.onChunk});

  final Future<void> Function(BridgeResponseFrame frame) onStart;
  final Future<void> Function(Uint8List chunkBytes) onChunk;

  Http2Headers? _headers;
  List<Cookie>? _cookies;
  final Completer<void> _done = Completer<void>();
  BridgeDetachedSocket? _detachedSocket;
  Future<void> _pendingWrite = Future<void>.value();
  bool _closed = false;
  bool _started = false;
  Encoding _encoding = utf8;

  bool get isClosed => _closed;

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
  HttpHeaders get headers => _headers ??= Http2Headers();

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
    _enqueueWrite(_ensureStarted);
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

    final headerNames = <String>[];
    final headerValues = <String>[];
    final headers = _headers;
    if (headers != null) {
      headers.forEach((name, values) {
        for (final value in values) {
          headerNames.add(name);
          headerValues.add(value);
        }
      });
    }
    final cookies = _cookies;
    if (cookies != null) {
      for (final cookie in cookies) {
        headerNames.add(HttpHeaders.setCookieHeader);
        headerValues.add(cookie.toString());
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
}

Future<BridgeDetachedSocket> _createDetachedSocketPair() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final bridgeSocketFuture = listener.first;
    final applicationSocketFuture = Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );

    final bridgeSocket = await bridgeSocketFuture;
    final applicationSocket = await applicationSocketFuture;
    try {
      bridgeSocket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    try {
      applicationSocket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    return BridgeDetachedSocket(
      applicationSocket: applicationSocket,
      bridgeSocket: bridgeSocket,
    );
  } finally {
    await listener.close();
  }
}
