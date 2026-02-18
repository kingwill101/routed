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

  _BridgeHttpHeaders? _headers;
  List<Cookie>? _cookies;
  final BytesBuilder _body = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  BridgeDetachedSocket? _detachedSocket;
  bool _closed = false;
  Encoding _encoding = utf8;

  Uint8List takeBodyBytes() =>
      _detachedSocket == null ? _body.takeBytes() : Uint8List(0);

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

    final headers = _headers;
    final cookies = _cookies;
    final headerCount =
        (headers?.flattenedHeaderValueCount ?? 0) + (cookies?.length ?? 0);
    final headerNames = headerCount == 0
        ? const <String>[]
        : List<String>.filled(headerCount, '', growable: false);
    final headerValues = headerCount == 0
        ? const <String>[]
        : List<String>.filled(headerCount, '', growable: false);

    if (headerCount != 0) {
      var offset = 0;
      if (headers != null) {
        offset = headers.writeFlattenedHeaderPairs(
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
}

/// Fast bridge response headers optimized for low cardinality writes.
final class _BridgeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = <String, List<String>>{};
  final Map<String, String> _originalNames = <String, String>{};
  final Set<String> _noFolding = <String>{};

  DateTime? _date;
  DateTime? _expires;
  DateTime? _ifModifiedSince;
  String? _host;
  int? _port;
  ContentType? _contentType;
  int _contentLength = -1;
  bool _persistentConnection = true;
  bool _chunkedTransferEncoding = false;

  @override
  DateTime? get date => _date;

  @override
  set date(DateTime? value) {
    _date = value;
    _setSingleValue(
      HttpHeaders.dateHeader,
      value == null ? null : HttpDate.format(value),
    );
  }

  @override
  DateTime? get expires => _expires;

  @override
  set expires(DateTime? value) {
    _expires = value;
    _setSingleValue(
      HttpHeaders.expiresHeader,
      value == null ? null : HttpDate.format(value),
    );
  }

  @override
  DateTime? get ifModifiedSince => _ifModifiedSince;

  @override
  set ifModifiedSince(DateTime? value) {
    _ifModifiedSince = value;
    _setSingleValue(
      HttpHeaders.ifModifiedSinceHeader,
      value == null ? null : HttpDate.format(value),
    );
  }

  @override
  String? get host => _host;

  @override
  set host(String? value) {
    _host = value;
    _updateHostHeader();
  }

  @override
  int? get port => _port;

  @override
  set port(int? value) {
    _port = value;
    _updateHostHeader();
  }

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
    _setSingleValue(
      HttpHeaders.contentTypeHeader,
      value == null ? null : value.toString(),
    );
  }

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
    if (value < 0) {
      _setSingleValue(HttpHeaders.contentLengthHeader, null);
      return;
    }
    _setSingleValue(HttpHeaders.contentLengthHeader, value.toString());
  }

  @override
  bool get persistentConnection => _persistentConnection;

  @override
  set persistentConnection(bool value) {
    _persistentConnection = value;
    if (value) {
      remove(HttpHeaders.connectionHeader, 'close');
      return;
    }
    _setSingleValue(HttpHeaders.connectionHeader, 'close');
  }

  @override
  bool get chunkedTransferEncoding => _chunkedTransferEncoding;

  @override
  set chunkedTransferEncoding(bool value) {
    _chunkedTransferEncoding = value;
    if (value) {
      _setSingleValue(HttpHeaders.transferEncodingHeader, 'chunked');
      return;
    }
    remove(HttpHeaders.transferEncodingHeader, 'chunked');
  }

  @override
  List<String>? operator [](String name) {
    final values = _headers[_normalize(name)];
    if (values == null) {
      return null;
    }
    return List<String>.from(values);
  }

  @override
  String? value(String name) {
    final values = _headers[_normalize(name)];
    if (values == null || values.isEmpty) {
      return null;
    }
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    final values = _headers.putIfAbsent(normalized, () => <String>[]);
    if (value is Iterable<Object?> && value is! String) {
      for (final item in value) {
        values.add(_valueToString(item));
      }
    } else {
      values.add(_valueToString(value));
    }
    _originalNames[normalized] = preserveHeaderCase ? name : normalized;
    _updateComputedFields(normalized);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    _headers.remove(normalized);
    _originalNames.remove(normalized);
    add(name, value, preserveHeaderCase: preserveHeaderCase);
  }

  @override
  void remove(String name, Object value) {
    final normalized = _normalize(name);
    final values = _headers[normalized];
    if (values == null) {
      return;
    }
    final toRemove = _valueToString(value);
    values.removeWhere((element) => element == toRemove);
    if (values.isEmpty) {
      _headers.remove(normalized);
      _originalNames.remove(normalized);
    }
    _updateComputedFields(normalized);
  }

  @override
  void removeAll(String name) {
    final normalized = _normalize(name);
    _headers.remove(normalized);
    _originalNames.remove(normalized);
    _updateComputedFields(normalized);
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    for (final entry in _headers.entries) {
      action(
        _originalNames[entry.key] ?? entry.key,
        List<String>.from(entry.value),
      );
    }
  }

  @override
  void noFolding(String name) {
    _noFolding.add(_normalize(name));
  }

  @override
  void clear() {
    _headers.clear();
    _originalNames.clear();
    _noFolding.clear();
    _date = null;
    _expires = null;
    _ifModifiedSince = null;
    _host = null;
    _port = null;
    _contentType = null;
    _contentLength = -1;
    _persistentConnection = true;
    _chunkedTransferEncoding = false;
  }

  int get flattenedHeaderValueCount {
    var count = 0;
    for (final values in _headers.values) {
      count += values.length;
    }
    return count;
  }

  int writeFlattenedHeaderPairs(
    List<String> headerNames,
    List<String> headerValues,
    int offset,
  ) {
    for (final entry in _headers.entries) {
      final originalName = _originalNames[entry.key] ?? entry.key;
      final values = entry.value;
      for (var i = 0; i < values.length; i++) {
        headerNames[offset] = originalName;
        headerValues[offset] = values[i];
        offset++;
      }
    }
    return offset;
  }

  @pragma('vm:prefer-inline')
  String _normalize(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Header name cannot be empty');
    }
    return _asciiLower(name);
  }

  @pragma('vm:prefer-inline')
  String _valueToString(Object? value) {
    if (value is DateTime) {
      return HttpDate.format(value);
    }
    if (value is HeaderValue) {
      return value.toString();
    }
    if (value is ContentType) {
      return value.toString();
    }
    return value.toString();
  }

  @pragma('vm:prefer-inline')
  void _setSingleValue(String name, String? value) {
    final normalized = _normalize(name);
    if (value == null) {
      _headers.remove(normalized);
      _originalNames.remove(normalized);
      _updateComputedFields(normalized);
      return;
    }
    _headers[normalized] = <String>[value];
    _originalNames[normalized] = normalized;
    _updateComputedFields(normalized);
  }

  @pragma('vm:prefer-inline')
  void _updateHostHeader() {
    final hostValue = _host;
    if (hostValue == null || hostValue.isEmpty) {
      _setSingleValue(HttpHeaders.hostHeader, null);
      return;
    }
    _setSingleValue(
      HttpHeaders.hostHeader,
      _port == null ? hostValue : '$hostValue:${_port!}',
    );
  }

  void _updateComputedFields(String key) {
    final values = _headers[key];
    switch (key) {
      case HttpHeaders.contentLengthHeader:
        _contentLength = values == null || values.isEmpty
            ? -1
            : int.tryParse(values.last.trim()) ?? -1;
        return;
      case HttpHeaders.contentTypeHeader:
        if (values == null || values.isEmpty) {
          _contentType = null;
          return;
        }
        try {
          _contentType = ContentType.parse(values.last);
        } catch (_) {
          _contentType = null;
        }
        return;
      case HttpHeaders.hostHeader:
        if (values == null || values.isEmpty) {
          _host = null;
          _port = null;
          return;
        }
        final hostValue = values.last;
        final colonIndex = hostValue.lastIndexOf(':');
        if (colonIndex != -1 &&
            colonIndex < hostValue.length - 1 &&
            int.tryParse(hostValue.substring(colonIndex + 1)) != null) {
          _host = hostValue.substring(0, colonIndex);
          _port = int.tryParse(hostValue.substring(colonIndex + 1));
          return;
        }
        _host = hostValue;
        _port = null;
        return;
      case HttpHeaders.dateHeader:
        _date = _parseHttpDate(values);
        return;
      case HttpHeaders.expiresHeader:
        _expires = _parseHttpDate(values);
        return;
      case HttpHeaders.ifModifiedSinceHeader:
        _ifModifiedSince = _parseHttpDate(values);
        return;
      case HttpHeaders.transferEncodingHeader:
        if (values == null) {
          _chunkedTransferEncoding = false;
          return;
        }
        _chunkedTransferEncoding = _containsTokenIgnoreCase(values, 'chunked');
        return;
      case HttpHeaders.connectionHeader:
        if (values == null || values.isEmpty) {
          _persistentConnection = true;
          return;
        }
        if (_containsTokenIgnoreCase(values, 'close')) {
          _persistentConnection = false;
          return;
        }
        if (_containsTokenIgnoreCase(values, 'keep-alive')) {
          _persistentConnection = true;
        }
        return;
    }
  }

  bool _containsTokenIgnoreCase(List<String> values, String token) {
    for (var i = 0; i < values.length; i++) {
      if (_equalsAsciiIgnoreCase(values[i], token)) {
        return true;
      }
    }
    return false;
  }

  DateTime? _parseHttpDate(List<String>? values) {
    if (values == null || values.isEmpty) {
      return null;
    }
    try {
      return HttpDate.parse(values.last);
    } catch (_) {
      return null;
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
