part of 'server_boot.dart';

/// {@template server_native_http_server_example}
/// Example:
/// ```dart
/// final server = await NativeHttpServer.bind(InternetAddress.loopbackIPv4, 8080);
/// await for (final request in server) {
///   request.response
///     ..statusCode = HttpStatus.ok
///     ..headers.contentType = ContentType.text
///     ..write('hello from server_native')
///     ..close();
/// }
/// ```
/// {@endtemplate}

/// `dart:io`-style HTTP server powered by the server_native transport.
///
/// This class implements [HttpServer] so existing `HttpServer` request handling
/// patterns can be reused with the Rust front transport.
///
/// {@macro server_native_http_server_example}
final class NativeHttpServer extends StreamView<HttpRequest>
    implements HttpServer {
  NativeHttpServer._(this._requestController, this._connectionCounters)
    : defaultResponseHeaders = _createNativeHttpDefaultResponseHeaders(),
      super(_requestController.stream);

  /// Binds a server similarly to [HttpServer.bind], including support for
  /// `"localhost"` and `"any"` convenience addresses.
  ///
  /// [nativeCallback] defaults to `true` and routes `HttpRequest` handling
  /// through the native callback transport (bridge socket bypassed).
  /// Set [nativeCallback] to `false` to use bridge socket transport.
  static Future<NativeHttpServer> bind(
    Object address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http2 = true,
    bool http3 = true,
    bool nativeCallback = true,
    Future<void>? shutdownSignal,
  }) => _nativeHttpServerBind(
    address,
    port,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    http2: http2,
    http3: http3,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
  );

  /// Binds on all loopback interfaces available on the host.
  ///
  /// [nativeCallback] defaults to `true` and routes `HttpRequest` handling
  /// through the native callback transport (bridge socket bypassed).
  /// Set [nativeCallback] to `false` to use bridge socket transport.
  static Future<NativeHttpServer> loopback(
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http2 = true,
    bool http3 = true,
    bool nativeCallback = true,
    Future<void>? shutdownSignal,
  }) => _nativeHttpServerLoopback(
    port,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    http2: http2,
    http3: http3,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
  );

  /// Binds a TLS server similarly to [HttpServer.bindSecure].
  ///
  /// [nativeCallback] defaults to `true` and routes `HttpRequest` handling
  /// through the native callback transport (bridge socket bypassed).
  /// Set [nativeCallback] to `false` to use bridge socket transport.
  static Future<NativeHttpServer> bindSecure(
    Object address,
    int port, {
    required String certificatePath,
    required String keyPath,
    String? certificatePassword,
    int backlog = 0,
    bool v6Only = false,
    bool requestClientCertificate = false,
    bool shared = false,
    bool http2 = true,
    bool http3 = true,
    bool nativeCallback = true,
    Future<void>? shutdownSignal,
  }) => _nativeHttpServerBindSecure(
    address,
    port,
    certificatePath: certificatePath,
    keyPath: keyPath,
    certificatePassword: certificatePassword,
    backlog: backlog,
    v6Only: v6Only,
    requestClientCertificate: requestClientCertificate,
    shared: shared,
    http2: http2,
    http3: http3,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
  );

  /// Binds a TLS server on all loopback interfaces available on the host.
  ///
  /// [nativeCallback] defaults to `true` and routes `HttpRequest` handling
  /// through the native callback transport (bridge socket bypassed).
  /// Set [nativeCallback] to `false` to use bridge socket transport.
  static Future<NativeHttpServer> loopbackSecure(
    int port, {
    required String certificatePath,
    required String keyPath,
    String? certificatePassword,
    int backlog = 0,
    bool v6Only = false,
    bool requestClientCertificate = false,
    bool shared = false,
    bool http2 = true,
    bool http3 = true,
    bool nativeCallback = true,
    Future<void>? shutdownSignal,
  }) => _nativeHttpServerLoopbackSecure(
    port,
    certificatePath: certificatePath,
    keyPath: keyPath,
    certificatePassword: certificatePassword,
    backlog: backlog,
    v6Only: v6Only,
    requestClientCertificate: requestClientCertificate,
    shared: shared,
    http2: http2,
    http3: http3,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
  );

  final StreamController<HttpRequest> _requestController;
  final _ProxyConnectionCounters _connectionCounters;
  final List<_NativeHttpBinding> _bindings = <_NativeHttpBinding>[];
  final Completer<void> _stopped = Completer<void>();
  final _NativeSessionStore _sessions = _NativeSessionStore(
    timeout: const Duration(minutes: 20),
  );
  int _sessionTimeoutSeconds = 20 * 60;
  int _runningBindingCount = 0;
  bool _closed = false;

  Future<void> _handleRequest(BridgeHttpRequest request) {
    if (_closed || _requestController.isClosed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      return request.response.close();
    }
    _applyNativeHttpRequestPolicies(
      request: request,
      sessions: _sessions,
      sessionTimeoutSeconds: _sessionTimeoutSeconds,
      autoCompress: autoCompress,
      defaultResponseHeaders: defaultResponseHeaders,
      serverHeader: serverHeader,
    );
    _requestController.add(request);
    return request.response.done;
  }

  void _completeIfStopped() {
    if (_stopped.isCompleted) {
      return;
    }
    if (_runningBindingCount > 0) {
      _runningBindingCount--;
    }
    if (_runningBindingCount != 0) {
      return;
    }
    _requestController.close();
    _stopped.complete();
  }

  @override
  String? serverHeader;

  @override
  final HttpHeaders defaultResponseHeaders;

  @override
  bool autoCompress = false;

  @override
  Duration? idleTimeout = const Duration(seconds: 120);

  @override
  int get port {
    if (_bindings.isEmpty) {
      return 0;
    }
    return _bindings.first.running.port;
  }

  @override
  InternetAddress get address {
    if (_bindings.isEmpty) {
      return InternetAddress.loopbackIPv4;
    }
    return _bindings.first.address;
  }

  @override
  set sessionTimeout(int timeout) {
    if (timeout < 0) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'sessionTimeout must be >= 0',
      );
    }
    _sessionTimeoutSeconds = timeout;
    _sessions.setTimeout(Duration(seconds: timeout));
  }

  @override
  HttpConnectionsInfo connectionsInfo() => _connectionCounters.snapshot();

  @override
  Future close({bool force = false}) async {
    if (_closed) {
      return _stopped.future;
    }
    _closed = true;
    await Future.wait(
      _bindings.map((binding) => binding.running.close(force: force)),
      eagerError: false,
    );
    await Future.wait(
      _bindings.map((binding) => binding.running.done),
      eagerError: false,
    );
    if (!_requestController.isClosed) {
      await _requestController.close();
    }
    if (!_stopped.isCompleted) {
      _stopped.complete();
    }
    _sessions.dispose();
    return _stopped.future;
  }
}
