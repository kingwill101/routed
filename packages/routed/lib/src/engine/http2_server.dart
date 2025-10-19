import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/transport.dart' as http2;

/// A function that handles a **single** HTTP 1.1 [HttpRequest].
typedef HttpRequestHandler = Future<void> Function(HttpRequest request);

/// A function that handles a single HTTP/2 [http2.ServerTransportStream].
///
/// The original TLS [Socket] that backs the stream is passed along so callers
/// can obtain peer information (for example, the client certificate).
typedef Http2StreamHandler =
    Future<void> Function(http2.ServerTransportStream stream, Socket socket);

/// Binds a secure [ServerSocket] that supports **both** HTTP 1.1 and HTTP/2.
///
/// The binding:
/// * Negotiates the protocol with ALPN (`h2`, `http/1.1`).
/// * For HTTP/2, creates a [http2.ServerTransportConnection].
/// * For HTTP 1.1, exposes a pseudo-[ServerSocket] so that an [HttpServer] can
///   consume incoming connections.
///
/// Call [start] to begin listening for traffic.
class Http2ServerBinding {
  Http2ServerBinding._(
    this._secureSocket,
    this._http11Controller,
    this.http1Server,
    this._settings,
  );

  final SecureServerSocket _secureSocket;
  final _ServerSocketController _http11Controller;
  final HttpServer http1Server;
  final http2.ServerSettings _settings;

  final _http2Connections = <http2.ServerTransportConnection, Socket>{};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _closed = false;

  /// The address the server is bound to.
  InternetAddress get address => _secureSocket.address;

  /// The port the server is bound to.
  int get port => _secureSocket.port;

  /// Creates and binds a new [Http2ServerBinding].
  ///
  /// The returned instance has not started processing connections yet; invoke
  /// [start] to attach request handlers.
  static Future<Http2ServerBinding> bind({
    required Object? address,
    required int port,
    required SecurityContext context,
    http2.ServerSettings? settings,
    bool v6Only = false,
    bool requestClientCertificate = false,
    bool shared = false,
  }) async {
    settings ??= const http2.ServerSettings();
    context.setAlpnProtocols(<String>['h2', 'http/1.1'], true);

    final secureSocket = await SecureServerSocket.bind(
      address,
      port,
      context,
      backlog: 0,
      v6Only: v6Only,
      requestClientCertificate: requestClientCertificate,
      shared: shared,
    );

    final http11Controller = _ServerSocketController(
      secureSocket.address,
      secureSocket.port,
    );
    final http11Server = HttpServer.listenOn(http11Controller.stream);

    return Http2ServerBinding._(
      secureSocket,
      http11Controller,
      http11Server,
      settings,
    );
  }

  /// Starts listening for incoming TLS connections.
  ///
  /// * `handleHttp11` is invoked for each HTTP 1.1 [HttpRequest].
  /// * `handleHttp2`  is invoked for each HTTP/2 stream.
  /// * `onError`      receives uncaught errors from both protocols.
  void start({
    required HttpRequestHandler handleHttp11,
    required Http2StreamHandler handleHttp2,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    _subscriptions.add(
      _secureSocket.listen((SecureSocket socket) {
        final protocol = socket.selectedProtocol;
        if (protocol == 'h2') {
          _bindHttp2Connection(socket, handleHttp2, onError);
        } else if (protocol == null || protocol == 'http/1.1') {
          _http11Controller.addHttp11Socket(socket);
        } else {
          // The peer requested an unsupported protocol.
          socket.destroy();
        }
      }, onError: onError),
    );

    _subscriptions.add(
      http1Server.listen(
        (HttpRequest request) async => handleHttp11(request),
        onError: onError,
      ),
    );
  }

  /// Gracefully closes the binding, its underlying sockets, and active streams.
  ///
  /// If [force] is `true`, outstanding HTTP/2 streams are terminated rather
  /// than finished gracefully.
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;

    await _secureSocket.close();
    await _http11Controller.close();
    await http1Server.close(force: force);

    final futures = <Future<void>>[];

    for (final entry in _http2Connections.entries) {
      final connection = entry.key;
      futures.add(force ? connection.terminate() : connection.finish());
      entry.value.destroy();
    }
    await Future.wait(futures);

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
  }

  void _bindHttp2Connection(
    Socket socket,
    Http2StreamHandler handleHttp2,
    void Function(Object error, StackTrace stackTrace)? onError,
  ) {
    final connection = http2.ServerTransportConnection.viaSocket(
      socket,
      settings: _settings,
    );
    _http2Connections[connection] = socket;

    connection.incomingStreams.listen(
      (stream) async => handleHttp2(stream, socket),
      onError: onError,
      onDone: () => _http2Connections.remove(connection),
    );
  }
}

class _ServerSocketController {
  _ServerSocketController(this.address, this.port)
    : _controller = StreamController<Socket>();

  final InternetAddress address;
  final int port;
  final StreamController<Socket> _controller;
  _StreamServerSocket? _artificialSocket;
  bool _closed = false;

  /// A synthetic [ServerSocket] that wraps the internal [Stream] of TLS sockets.
  _StreamServerSocket get stream => _artificialSocket ??= _StreamServerSocket(
    address,
    port,
    _controller.stream,
    _closeController,
  );

  void addHttp11Socket(Socket socket) {
    _controller.add(socket);
  }

  Future<void> close() => _closeController();

  Future<void> _closeController() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

class _StreamServerSocket extends StreamView<Socket> implements ServerSocket {
  _StreamServerSocket(
    this._address,
    this._port,
    super.stream,
    this._closeCallback,
  );

  final InternetAddress _address;
  final int _port;
  final Future<void> Function() _closeCallback;
  bool _closed = false;

  @override
  InternetAddress get address => _address;

  @override
  int get port => _port;

  @override
  Future<ServerSocket> close() async {
    if (_closed) return this;
    _closed = true;
    await _closeCallback();
    return this;
  }
}

/// A mutable implementation of [HttpHeaders] backed by a `Map`.
///
/// The class keeps derived header fields (for example, `contentLength`) in
/// sync with their string representations. It does **not** perform any
/// validation beyond what `dart:io` already provides.
class Http2Headers implements HttpHeaders {
  Http2Headers();

  final Map<String, List<String>> _headers = <String, List<String>>{};
  final Map<String, String> _originalNames = <String, String>{};
  final Set<String> _noFolding = <String>{};
  bool _suppressFieldUpdates = false;

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
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.dateHeader,
        value == null ? null : <String>[HttpDate.format(value)],
      ),
    );
  }

  @override
  DateTime? get expires => _expires;

  @override
  set expires(DateTime? value) {
    _expires = value;
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.expiresHeader,
        value == null ? null : <String>[HttpDate.format(value)],
      ),
    );
  }

  @override
  DateTime? get ifModifiedSince => _ifModifiedSince;

  @override
  set ifModifiedSince(DateTime? value) {
    _ifModifiedSince = value;
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.ifModifiedSinceHeader,
        value == null ? null : <String>[HttpDate.format(value)],
      ),
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
    _runWithoutUpdate(
      () => _setValues(
        HttpHeaders.contentTypeHeader,
        value == null ? null : <String>[value.toString()],
      ),
    );
  }

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
    _runWithoutUpdate(() {
      if (value < 0) {
        _setValues(HttpHeaders.contentLengthHeader, null);
      } else {
        _setValues(HttpHeaders.contentLengthHeader, <String>[value.toString()]);
      }
    });
  }

  @override
  bool get persistentConnection => _persistentConnection;

  @override
  set persistentConnection(bool value) {
    _persistentConnection = value;
    _runWithoutUpdate(() {
      if (value) {
        remove(HttpHeaders.connectionHeader, 'close');
      } else {
        _setValues(HttpHeaders.connectionHeader, <String>['close']);
      }
    });
  }

  @override
  bool get chunkedTransferEncoding => _chunkedTransferEncoding;

  @override
  set chunkedTransferEncoding(bool value) {
    _chunkedTransferEncoding = value;
    _runWithoutUpdate(() {
      if (value) {
        _setValues(HttpHeaders.transferEncodingHeader, <String>['chunked']);
      } else {
        remove(HttpHeaders.transferEncodingHeader, 'chunked');
      }
    });
  }

  @override
  List<String>? operator [](String name) {
    final normalized = _normalize(name);
    final values = _headers[normalized];
    return values == null ? null : List<String>.from(values);
  }

  @override
  String? value(String name) {
    final normalized = _normalize(name);
    final values = _headers[normalized];
    if (values == null || values.isEmpty) return null;
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    final values = _headers.putIfAbsent(normalized, () => <String>[]);
    if (value is Iterable && value is! String) {
      for (final v in value) {
        values.add(_valueToString(v));
      }
    } else {
      values.add(_valueToString(value));
    }
    if (preserveHeaderCase) {
      _originalNames[normalized] = name;
    } else {
      _originalNames.putIfAbsent(normalized, () => name);
    }
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
    if (values == null) return;
    final stringValue = _valueToString(value);
    values.removeWhere((element) => element == stringValue);
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
    _headers.forEach((key, values) {
      final originalName = _originalNames[key] ?? key;
      action(originalName, List<String>.from(values));
    });
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

  Iterable<String> get keys sync* {
    for (final entry in _headers.entries) {
      yield _originalNames[entry.key] ?? entry.key;
    }
  }

  String _normalize(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Header name cannot be empty');
    }
    return name.toLowerCase();
  }

  String _valueToString(Object? value) {
    if (value is DateTime) return HttpDate.format(value);
    if (value is HeaderValue) return value.toString();
    if (value is ContentType) return value.toString();
    return value.toString();
  }

  void _updateHostHeader() {
    final hostValue = _host;
    _runWithoutUpdate(() {
      if (hostValue == null || hostValue.isEmpty) {
        _setValues(HttpHeaders.hostHeader, null);
        return;
      }
      final combined = _port != null ? '$hostValue:${_port!}' : hostValue;
      _setValues(HttpHeaders.hostHeader, <String>[combined]);
    });
  }

  void _setValues(String name, List<String>? values) {
    final key = _normalize(name);
    if (values == null || values.isEmpty) {
      _headers.remove(key);
      _originalNames.remove(key);
    } else {
      _headers[key] = List<String>.from(values);
      _originalNames.putIfAbsent(key, () => name);
    }
    if (!_suppressFieldUpdates) _updateComputedFields(key);
  }

  void _runWithoutUpdate(void Function() action) {
    final previous = _suppressFieldUpdates;
    _suppressFieldUpdates = true;
    try {
      action();
    } finally {
      _suppressFieldUpdates = previous;
    }
  }

  void _updateComputedFields(String key) {
    if (_suppressFieldUpdates) return;
    final values = _headers[key];
    switch (key) {
      case HttpHeaders.contentLengthHeader:
        _contentLength = values == null || values.isEmpty
            ? -1
            : int.tryParse(values.last.trim()) ?? -1;
        break;
      case HttpHeaders.contentTypeHeader:
        if (values == null || values.isEmpty) {
          _contentType = null;
        } else {
          try {
            _contentType = ContentType.parse(values.last);
          } catch (_) {
            _contentType = null;
          }
        }
        break;
      case HttpHeaders.hostHeader:
        if (values == null || values.isEmpty) {
          _host = null;
          _port = null;
        } else {
          final hostValue = values.last;
          final colonIndex = hostValue.lastIndexOf(':');
          if (colonIndex != -1 &&
              colonIndex < hostValue.length - 1 &&
              int.tryParse(hostValue.substring(colonIndex + 1)) != null) {
            _host = hostValue.substring(0, colonIndex);
            _port = int.tryParse(hostValue.substring(colonIndex + 1));
          } else {
            _host = hostValue;
            _port = null;
          }
        }
        break;
      case HttpHeaders.dateHeader:
        _date = _parseHttpDate(values);
        break;
      case HttpHeaders.expiresHeader:
        _expires = _parseHttpDate(values);
        break;
      case HttpHeaders.ifModifiedSinceHeader:
        _ifModifiedSince = _parseHttpDate(values);
        break;
      case HttpHeaders.transferEncodingHeader:
        _chunkedTransferEncoding = values == null
            ? false
            : values.any((value) => value.toLowerCase() == 'chunked');
        break;
      case HttpHeaders.connectionHeader:
        if (values == null || values.isEmpty) {
          _persistentConnection = true;
        } else {
          final lowered = values.map((value) => value.toLowerCase());
          if (lowered.contains('close')) {
            _persistentConnection = false;
          } else if (lowered.contains('keep-alive')) {
            _persistentConnection = true;
          }
        }
        break;
    }
  }

  DateTime? _parseHttpDate(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    try {
      return HttpDate.parse(values.last);
    } catch (_) {
      return null;
    }
  }
}

/// An [HttpRequest] implementation that adapts an HTTP/2 stream to the
/// familiar `dart:io` API.
///
/// The request body is exposed as a broadcast stream of [Uint8List] chunks.
class Http2HttpRequestAdapter extends Stream<Uint8List> implements HttpRequest {
  Http2HttpRequestAdapter({
    required this.method,
    required this.requestedUri,
    required HttpHeaders headers,
    required this.response,
    required Stream<Uint8List> bodyStream,
    required this.connectionInfo,
    required this.isSecureConnection,
    this.certificate,
  }) : _headers = headers,
       _bodyStream = bodyStream.asBroadcastStream() {
    // Parse incoming cookies.
    final cookieValues = headers[HttpHeaders.cookieHeader];
    if (cookieValues != null) {
      for (final header in cookieValues) {
        for (final part in header.split(';')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final idx = trimmed.indexOf('=');
          if (idx == -1) {
            cookies.add(Cookie(trimmed, ''));
          } else {
            final name = trimmed.substring(0, idx).trim();
            final value = trimmed.substring(idx + 1).trim();
            cookies.add(Cookie(name, value));
          }
        }
      }
    }
  }

  @override
  final String method;

  @override
  final Uri requestedUri;

  @override
  Uri get uri => requestedUri;

  final HttpHeaders _headers;

  @override
  HttpHeaders get headers => _headers;

  @override
  final List<Cookie> cookies = <Cookie>[];

  bool _persistentConnection = true;

  @override
  bool get persistentConnection => _persistentConnection;

  set persistentConnection(bool value) => _persistentConnection = value;

  @override
  final X509Certificate? certificate;

  @override
  final HttpSession session = _Http2Session();

  @override
  String get protocolVersion => '2.0';

  @override
  final HttpConnectionInfo? connectionInfo;

  @override
  HttpResponse response;

  @override
  int get contentLength => headers.contentLength;

  ContentType? get contentType => headers.contentType;

  bool get isSecure => isSecureConnection;

  final bool isSecureConnection;
  final Stream<Uint8List> _bodyStream;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _bodyStream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  Future<Socket> detachSocket({bool writeHeaders = true}) =>
      throw UnsupportedError('detachSocket is not supported for HTTP/2');

  Future<HttpClientResponse> upgrade(
    Future<void> Function(Socket) readHandler,
  ) => throw UnsupportedError('upgrade is not supported for HTTP/2');
}

/// An [HttpResponse] implementation that writes HTTP/2 frames.
///
/// The response automatically converts header/cookie additions into the
/// appropriate `HEADERS` frame when data is sent for the first time.
class Http2HttpResponseAdapter implements HttpResponse {
  Http2HttpResponseAdapter(this._stream, {this.isSecure = true})
    : _headers = Http2Headers();

  final http2.ServerTransportStream _stream;
  final bool isSecure;

  bool _headersSent = false;
  bool _closed = false;
  final Completer<void> _done = Completer<void>();
  final List<Cookie> _cookies = <Cookie>[];
  Encoding _encoding = utf8;

  @override
  int get contentLength => headers.contentLength;

  @override
  set contentLength(int value) => headers.contentLength = value;

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

  final Http2Headers _headers;

  @override
  HttpHeaders get headers => _headers;

  @override
  List<Cookie> get cookies => List<Cookie>.unmodifiable(_cookies);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void add(List<int> data) {
    _ensureHeadersSent();
    if (_closed) throw StateError('Response is already closed');
    _stream.sendData(data);
  }

  void _ensureHeadersSent() {
    if (_headersSent) return;

    final headerFrames = <http2.Header>[
      http2.Header.ascii(':status', '$statusCode'),
    ];

    headers.forEach((name, values) {
      for (final value in values) {
        headerFrames.add(http2.Header.ascii(name.toLowerCase(), value));
      }
    });

    for (final cookie in _cookies) {
      headerFrames.add(
        http2.Header.ascii(HttpHeaders.setCookieHeader, cookie.toString()),
      );
    }

    _stream.sendHeaders(headerFrames, endStream: false);
    _headersSent = true;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
    _stream.outgoingMessages.addError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ensureHeadersSent();
    _stream.sendData(const <int>[], endStream: true);
    _stream.outgoingMessages.close();
    if (!_done.isCompleted) _done.complete();
    await _done.future;
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
  }) {
    headers.set(HttpHeaders.locationHeader, location.toString());
    statusCode = status;
    return close();
  }

  @override
  HttpConnectionInfo? get connectionInfo => null;

  void setCookie(Cookie cookie) {
    _cookies.add(cookie);
    headers.add(HttpHeaders.setCookieHeader, cookie.toString());
  }

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) =>
      throw UnsupportedError('detachSocket is not supported for HTTP/2');
}

class _Http2Session extends MapBase<dynamic, dynamic> implements HttpSession {
  @override
  String id = '';

  @override
  bool isNew = false;

  final Map<String, dynamic> _data = <String, dynamic>{};

  Duration timeout = const Duration(minutes: 20);

  @override
  void destroy() => _data.clear();

  @override
  set onTimeout(void Function() callback) {
    // HTTP/2 adapter does not manage timers; callers must handle timeout logic.
  }

  HttpSession get session => this;

  @override
  dynamic operator [](Object? key) => key is String ? _data[key] : null;

  @override
  void clear() => _data.clear();

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  void operator []=(Object? key, dynamic value) {
    if (key is! String) throw ArgumentError('Session keys must be strings');
    _data[key] = value;
  }

  @override
  dynamic remove(Object? key) => key is String ? _data.remove(key) : null;
}

/// Factory utilities for adapting HTTP/2 streams to `dart:io` request objects.
class Http2Adapter {
  /// Converts an HTTP/2 [stream] into an [HttpRequest] that can be handled by
  /// standard `dart:io`-based middleware.
  static Future<HttpRequest> createHttpRequest(
    http2.ServerTransportStream stream,
    Socket socket,
  ) async {
    final messages = StreamIterator(stream.incomingMessages);
    if (!await messages.moveNext()) {
      throw StateError('HTTP/2 stream closed before headers received');
    }
    final first = messages.current;
    if (first is! http2.HeadersStreamMessage) {
      throw StateError('Expected headers frame as first message');
    }

    final headerMap = <String, List<String>>{};
    String? method;
    String? scheme;
    String? path;
    String? authority;

    for (final header in first.headers) {
      final name = ascii.decode(header.name).toLowerCase();
      final value = utf8.decode(header.value);
      switch (name) {
        case ':method':
          method = value;
          break;
        case ':scheme':
          scheme = value;
          break;
        case ':path':
          path = value;
          break;
        case ':authority':
          authority = value;
          break;
        default:
          headerMap.putIfAbsent(name, () => <String>[]).add(value);
      }
    }

    if (method == null || scheme == null || path == null || authority == null) {
      throw StateError('Missing mandatory HTTP/2 pseudo headers');
    }

    final requestedUri = Uri.parse('$scheme://$authority$path');
    headerMap
        .putIfAbsent(HttpHeaders.hostHeader, () => <String>[])
        .add(authority);

    Stream<Uint8List> bodyStream() async* {
      try {
        while (await messages.moveNext()) {
          final message = messages.current;
          if (message is http2.DataStreamMessage) {
            final data = message.bytes;
            yield data is Uint8List ? data : Uint8List.fromList(data);
            if (message.endStream) break;
          } else if (message.endStream) {
            break;
          }
        }
      } finally {
        await messages.cancel();
      }
    }

    final httpHeaders = Http2Headers();
    headerMap.forEach((name, values) {
      for (final value in values) {
        httpHeaders.add(name, value);
      }
    });

    // The engine pipeline closes the response when handling completes.
    // ignore: close_sinks
    final responseAdapter = Http2HttpResponseAdapter(stream);

    final connectionInfo = _Http2ConnectionInfo(
      remoteAddress: socket.remoteAddress,
      remotePort: socket.remotePort,
      localAddress: socket.address,
      localPort: socket.port,
    );

    return Http2HttpRequestAdapter(
      method: method,
      requestedUri: requestedUri,
      headers: httpHeaders,
      response: responseAdapter,
      bodyStream: bodyStream(),
      connectionInfo: connectionInfo,
      isSecureConnection: socket is SecureSocket,
      certificate: socket is SecureSocket ? socket.peerCertificate : null,
    );
  }
}

class _Http2ConnectionInfo implements HttpConnectionInfo {
  _Http2ConnectionInfo({
    required InternetAddress remoteAddress,
    required int remotePort,
    required InternetAddress localAddress,
    required int localPort,
  }) : _remoteAddress = remoteAddress,
       _remotePort = remotePort,
       _localAddress = localAddress,
       _localPort = localPort;

  final InternetAddress _remoteAddress;
  final int _remotePort;
  final InternetAddress _localAddress;
  final int _localPort;

  @override
  InternetAddress get remoteAddress => _remoteAddress;

  @override
  int get remotePort => _remotePort;

  InternetAddress get localAddress => _localAddress;

  @override
  int get localPort => _localPort;
}
