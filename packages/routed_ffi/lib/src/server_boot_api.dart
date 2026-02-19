part of 'server_boot.dart';

/// {@template server_native_transport_overview}
/// server_native transport APIs expose a `dart:io`-like server experience while
/// keeping Rust as the front-line network transport.
///
/// Typical flow:
/// 1. Bind one or more listeners.
/// 2. Receive requests as either `HttpRequest` or direct request views.
/// 3. Write responses and close.
/// {@endtemplate}
///
/// {@template server_native_direct_handler_example}
/// Example:
/// ```dart
/// await serveNativeDirect((request) async {
///   if (request.path == '/health') {
///     return NativeDirectResponse.bytes(
///       status: HttpStatus.ok,
///       headers: const <MapEntry<String, String>>[
///         MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
///       ],
///       bodyBytes: Uint8List.fromList('ok'.codeUnits),
///     );
///   }
///   return NativeDirectResponse.bytes(status: HttpStatus.notFound);
/// }, host: InternetAddress.loopbackIPv4, port: 8080);
/// ```
/// {@endtemplate}
///
/// {@template server_native_multi_bind_example}
/// Example:
/// ```dart
/// await serveNativeMulti(
///   engine,
///   binds: const <NativeServerBind>[
///     NativeServerBind(host: '127.0.0.1', port: 8080),
///     NativeServerBind(host: '::1', port: 8080),
///   ],
/// );
/// ```
/// {@endtemplate}

/// Request delivered to a direct FFI handler without Routed engine wrapping.
///
/// {@macro server_native_transport_overview}
///
/// This request view avoids allocating Routed HTTP abstractions and is useful
/// when handlers only need method/uri/header/body primitives.
final class NativeDirectRequest {
  /// Creates a request object from explicit fields.
  NativeDirectRequest({
    required String method,
    required String scheme,
    required String authority,
    required String path,
    required String query,
    required String protocol,
    required List<MapEntry<String, String>> headers,
    required this.body,
  }) : _frame = null,
       _payload = null,
       _method = method,
       _scheme = scheme,
       _authority = authority,
       _path = path,
       _query = query,
       _protocol = protocol,
       _headers = List<MapEntry<String, String>>.unmodifiable(headers);

  NativeDirectRequest._fromFrame(this._frame, this.body)
    : _payload = null,
      _method = null,
      _scheme = null,
      _authority = null,
      _path = null,
      _query = null,
      _protocol = null,
      _headers = null;

  NativeDirectRequest._fromPayload(this._payload, this.body)
    : _frame = null,
      _method = null,
      _scheme = null,
      _authority = null,
      _path = null,
      _query = null,
      _protocol = null,
      _headers = null;

  final BridgeRequestFrame? _frame;
  final _DirectPayloadRequestView? _payload;
  final String? _method;
  final String? _scheme;
  final String? _authority;
  final String? _path;
  final String? _query;
  final String? _protocol;
  List<MapEntry<String, String>>? _headers;

  /// Request body stream.
  final Stream<Uint8List> body;

  /// HTTP method (for example `GET`, `POST`).
  String get method => _frame?.method ?? _payload?.method ?? _method!;

  /// URL scheme (`http`, `https`, ...).
  String get scheme => _frame?.scheme ?? _payload?.scheme ?? _scheme!;

  /// Authority portion (`host[:port]`).
  String get authority =>
      _frame?.authority ?? _payload?.authority ?? _authority!;

  /// Request path (`/foo/bar`).
  String get path => _frame?.path ?? _payload?.path ?? _path!;

  /// Raw query string without leading `?`.
  String get query => _frame?.query ?? _payload?.query ?? _query!;

  /// HTTP protocol version string (`1.1`, `2`, ...).
  String get protocol => _frame?.protocol ?? _payload?.protocol ?? _protocol!;

  /// Header list preserving repeated values.
  List<MapEntry<String, String>> get headers {
    final headers = _headers;
    if (headers != null) {
      return headers;
    }
    final frame = _frame;
    if (frame == null) {
      final payload = _payload;
      if (payload == null) {
        return const <MapEntry<String, String>>[];
      }
      final view = UnmodifiableListView(payload.materializeHeaders());
      _headers = view;
      return view;
    }
    final view = UnmodifiableListView(_DirectHeaderListView(frame));
    _headers = view;
    return view;
  }

  /// Parsed request URI reconstructed from scheme/authority/path/query.
  late final Uri uri = _buildDirectUri(
    scheme: scheme,
    authority: authority,
    path: path,
    query: query,
  );

  /// Returns the first header value for [name], or `null`.
  ///
  /// Matching is ASCII case-insensitive.
  String? header(String name) {
    final frame = _frame;
    if (frame != null) {
      for (var i = 0; i < frame.headerCount; i++) {
        final headerName = frame.headerNameAt(i);
        if (identical(headerName, name) ||
            headerName == name ||
            _equalsAsciiIgnoreCase(headerName, name)) {
          return frame.headerValueAt(i);
        }
      }
      return null;
    }
    final payload = _payload;
    if (payload != null) {
      return payload.header(name);
    }

    final target = name;
    for (final entry in headers) {
      if (_equalsAsciiIgnoreCase(entry.key, target)) {
        return entry.value;
      }
    }
    return null;
  }
}

/// Response returned by [NativeDirectHandler].
///
/// {@macro server_native_direct_handler_example}
final class NativeDirectResponse {
  /// Creates an in-memory bytes response.
  NativeDirectResponse.bytes({
    this.status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    Uint8List? bodyBytes,
  }) : headers = List<MapEntry<String, String>>.of(headers),
       bodyBytes = bodyBytes ?? Uint8List(0),
       body = null,
       encodedBridgePayload = null;

  /// Creates a streaming response.
  NativeDirectResponse.stream({
    this.status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    required this.body,
  }) : headers = List<MapEntry<String, String>>.of(headers),
       bodyBytes = null,
       encodedBridgePayload = null;

  /// Returns a response backed by a pre-encoded bridge payload.
  ///
  /// This avoids per-request Dart response encoding when the same response can
  /// be reused (for example, static benchmark responses).
  NativeDirectResponse.encodedPayload({
    required Uint8List bridgeResponsePayload,
  }) : status = HttpStatus.ok,
       headers = const <MapEntry<String, String>>[],
       bodyBytes = null,
       body = null,
       encodedBridgePayload = bridgeResponsePayload {
    BridgeResponseFrame.decodePayload(bridgeResponsePayload);
  }

  /// Builds and caches a single encoded bridge response payload.
  factory NativeDirectResponse.preEncodedBytes({
    int status = HttpStatus.ok,
    List<MapEntry<String, String>> headers = const <MapEntry<String, String>>[],
    Uint8List? bodyBytes,
  }) {
    final frame = BridgeResponseFrame(
      status: status,
      headers: headers,
      bodyBytes: bodyBytes ?? Uint8List(0),
    );
    return NativeDirectResponse.encodedPayload(
      bridgeResponsePayload: frame.encodePayload(),
    );
  }

  /// Status code.
  final int status;

  /// Response headers.
  final List<MapEntry<String, String>> headers;

  /// Full response bytes for non-streaming responses.
  final Uint8List? bodyBytes;

  /// Streamed response body for streaming responses.
  final Stream<Uint8List>? body;

  /// Optional pre-encoded bridge response payload.
  final Uint8List? encodedBridgePayload;
}

/// Direct callback signature used by [serveNativeDirect] and
/// [serveSecureNativeDirect].
typedef NativeDirectHandler =
    FutureOr<NativeDirectResponse> Function(NativeDirectRequest request);

typedef _BridgeHandleFrame =
    Future<_BridgeHandleFrameResult> Function(BridgeRequestFrame frame);

typedef _BridgeHandlePayload =
    Future<_BridgeHandleFrameResult> Function(Uint8List payload);

typedef _BridgeHandleStream =
    Future<void> Function({
      required BridgeRequestFrame frame,
      required Stream<Uint8List> bodyStream,
      required Future<void> Function(BridgeResponseFrame frame) onResponseStart,
      required Future<void> Function(Uint8List chunkBytes) onResponseChunk,
    });

/// Listener binding config for FFI server boot helpers.
///
/// Use this with [serveNativeMulti] and [serveSecureNativeMulti] to expose one
/// logical engine on multiple host/port listeners.
///
/// {@macro server_native_multi_bind_example}
final class NativeServerBind {
  /// Creates a bind configuration.
  const NativeServerBind({this.host = '127.0.0.1', this.port = 0});

  /// Host/address to bind.
  ///
  /// Accepts a [String] or [InternetAddress].
  final Object host;

  /// TCP port to bind.
  final int port;
}

/// `http_multi_server`-style bind helpers for server_native transport boot.
///
/// This mirrors the address semantics of `HttpMultiServer`:
/// - `'localhost'`: bind both loopback interfaces when available.
/// - `'any'`: bind `InternetAddress.anyIPv6` when supported, else IPv4.
///
/// {@macro server_native_transport_overview}
final class NativeMultiServer {
  /// Boots server_native transport on all available loopback interfaces.
  ///
  /// For `port == 0`, a shared ephemeral port is reserved first so both
  /// loopback listeners use the same port.
  static Future<void> loopback(
    Engine engine,
    int port, {
    bool echo = true,
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http3 = true,
    bool nativeCallback = false,
    Future<void>? shutdownSignal,
  }) async {
    final binds = await _loopbackBinds(port);
    await serveNativeMulti(
      engine,
      binds: binds,
      echo: echo,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Boots server_native TLS transport on all available loopback interfaces.
  ///
  /// For `port == 0`, a shared ephemeral port is reserved first so both
  /// loopback listeners use the same port.
  static Future<void> loopbackSecure(
    Engine engine,
    int port, {
    required String certificatePath,
    required String keyPath,
    String? certificatePassword,
    int backlog = 0,
    bool v6Only = false,
    bool requestClientCertificate = false,
    bool shared = false,
    bool http3 = true,
    bool nativeCallback = false,
    Future<void>? shutdownSignal,
  }) async {
    final binds = await _loopbackBinds(port);
    await serveSecureNativeMulti(
      engine,
      binds: binds,
      certificatePath: certificatePath,
      keyPath: keyPath,
      certificatePassword: certificatePassword,
      backlog: backlog,
      v6Only: v6Only,
      requestClientCertificate: requestClientCertificate,
      shared: shared,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Boots server_native transport with `HttpMultiServer` address semantics.
  ///
  /// For `'localhost'` behaves like [loopback].
  ///
  /// For `'any'` listens on [InternetAddress.anyIPv6] when IPv6 is available,
  /// else [InternetAddress.anyIPv4].
  static Future<void> bind(
    Engine engine,
    Object address,
    int port, {
    bool echo = true,
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http3 = true,
    bool nativeCallback = false,
    Future<void>? shutdownSignal,
  }) async {
    final normalized = _normalizeBindHost(address, 'address');
    if (normalized == 'localhost') {
      return loopback(
        engine,
        port,
        echo: echo,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        http3: http3,
        nativeCallback: nativeCallback,
        shutdownSignal: shutdownSignal,
      );
    }
    if (normalized == 'any') {
      final host = await _anyHost();
      return serveNative(
        engine,
        host: host,
        port: port,
        echo: echo,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        http3: http3,
        nativeCallback: nativeCallback,
        shutdownSignal: shutdownSignal,
      );
    }
    return serveNative(
      engine,
      host: normalized,
      port: port,
      echo: echo,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Boots server_native TLS transport with `HttpMultiServer` address semantics.
  ///
  /// For `'localhost'` behaves like [loopbackSecure].
  ///
  /// For `'any'` listens on [InternetAddress.anyIPv6] when IPv6 is available,
  /// else [InternetAddress.anyIPv4].
  static Future<void> bindSecure(
    Engine engine,
    Object address,
    int port, {
    required String certificatePath,
    required String keyPath,
    String? certificatePassword,
    int backlog = 0,
    bool v6Only = false,
    bool requestClientCertificate = false,
    bool shared = false,
    bool http3 = true,
    bool nativeCallback = false,
    Future<void>? shutdownSignal,
  }) async {
    final normalized = _normalizeBindHost(address, 'address');
    if (normalized == 'localhost') {
      return loopbackSecure(
        engine,
        port,
        certificatePath: certificatePath,
        keyPath: keyPath,
        certificatePassword: certificatePassword,
        backlog: backlog,
        v6Only: v6Only,
        requestClientCertificate: requestClientCertificate,
        shared: shared,
        http3: http3,
        nativeCallback: nativeCallback,
        shutdownSignal: shutdownSignal,
      );
    }
    if (normalized == 'any') {
      final host = await _anyHost();
      return serveSecureNative(
        engine,
        address: host,
        port: port,
        certificatePath: certificatePath,
        keyPath: keyPath,
        certificatePassword: certificatePassword,
        backlog: backlog,
        v6Only: v6Only,
        requestClientCertificate: requestClientCertificate,
        shared: shared,
        http3: http3,
        nativeCallback: nativeCallback,
        shutdownSignal: shutdownSignal,
      );
    }
    return serveSecureNative(
      engine,
      address: normalized,
      port: port,
      certificatePath: certificatePath,
      keyPath: keyPath,
      certificatePassword: certificatePassword,
      backlog: backlog,
      v6Only: v6Only,
      requestClientCertificate: requestClientCertificate,
      shared: shared,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }
}
