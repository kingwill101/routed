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

final class _FfiHttpBinding {
  _FfiHttpBinding({required this.address, required this.running});

  final InternetAddress address;
  final _RunningProxy running;
}

/// `dart:io`-style HTTP server powered by the server_native transport.
///
/// This class implements [HttpServer] so existing `HttpServer` request handling
/// patterns can be reused with the Rust front transport.
///
/// {@macro server_native_http_server_example}
final class NativeHttpServer extends StreamView<HttpRequest>
    implements HttpServer {
  NativeHttpServer._(this._requestController, this._connectionCounters)
    : defaultResponseHeaders = _createDefaultResponseHeaders(),
      super(_requestController.stream);

  /// Binds a server similarly to [HttpServer.bind], including support for
  /// `"localhost"` and `"any"` convenience addresses.
  static Future<NativeHttpServer> bind(
    Object address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http3 = true,
    Future<void>? shutdownSignal,
  }) async {
    final normalizedAddress = _normalizeBindHost(address, 'address');
    if (normalizedAddress == 'localhost') {
      return loopback(
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        http3: http3,
        shutdownSignal: shutdownSignal,
      );
    }
    if (normalizedAddress == 'any') {
      return _start(
        binds: <FfiServerBind>[
          FfiServerBind(host: await _anyHost(), port: port),
        ],
        secure: false,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        requestClientCertificate: false,
        http3: http3,
        shutdownSignal: shutdownSignal,
      );
    }
    return _start(
      binds: <FfiServerBind>[
        FfiServerBind(host: normalizedAddress, port: port),
      ],
      secure: false,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      requestClientCertificate: false,
      http3: http3,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Binds on all loopback interfaces available on the host.
  static Future<NativeHttpServer> loopback(
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http3 = true,
    Future<void>? shutdownSignal,
  }) async {
    return _start(
      binds: await _loopbackBinds(port),
      secure: false,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      requestClientCertificate: false,
      http3: http3,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Binds a TLS server similarly to [HttpServer.bindSecure].
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
    bool http3 = true,
    Future<void>? shutdownSignal,
  }) async {
    final normalizedAddress = _normalizeBindHost(address, 'address');
    if (normalizedAddress == 'localhost') {
      return loopbackSecure(
        port,
        certificatePath: certificatePath,
        keyPath: keyPath,
        certificatePassword: certificatePassword,
        backlog: backlog,
        v6Only: v6Only,
        requestClientCertificate: requestClientCertificate,
        shared: shared,
        http3: http3,
        shutdownSignal: shutdownSignal,
      );
    }
    if (normalizedAddress == 'any') {
      return _start(
        binds: <FfiServerBind>[
          FfiServerBind(host: await _anyHost(), port: port),
        ],
        secure: true,
        certificatePath: certificatePath,
        keyPath: keyPath,
        certificatePassword: certificatePassword,
        backlog: backlog,
        v6Only: v6Only,
        requestClientCertificate: requestClientCertificate,
        shared: shared,
        http3: http3,
        shutdownSignal: shutdownSignal,
      );
    }
    return _start(
      binds: <FfiServerBind>[
        FfiServerBind(host: normalizedAddress, port: port),
      ],
      secure: true,
      certificatePath: certificatePath,
      keyPath: keyPath,
      certificatePassword: certificatePassword,
      backlog: backlog,
      v6Only: v6Only,
      requestClientCertificate: requestClientCertificate,
      shared: shared,
      http3: http3,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Binds a TLS server on all loopback interfaces available on the host.
  static Future<NativeHttpServer> loopbackSecure(
    int port, {
    required String certificatePath,
    required String keyPath,
    String? certificatePassword,
    int backlog = 0,
    bool v6Only = false,
    bool requestClientCertificate = false,
    bool shared = false,
    bool http3 = true,
    Future<void>? shutdownSignal,
  }) async {
    return _start(
      binds: await _loopbackBinds(port),
      secure: true,
      certificatePath: certificatePath,
      keyPath: keyPath,
      certificatePassword: certificatePassword,
      backlog: backlog,
      v6Only: v6Only,
      requestClientCertificate: requestClientCertificate,
      shared: shared,
      http3: http3,
      shutdownSignal: shutdownSignal,
    );
  }

  static Future<NativeHttpServer> _start({
    required List<FfiServerBind> binds,
    required bool secure,
    String? certificatePath,
    String? keyPath,
    String? certificatePassword,
    required int backlog,
    required bool v6Only,
    required bool requestClientCertificate,
    required bool shared,
    required bool http3,
    Future<void>? shutdownSignal,
  }) async {
    if (binds.isEmpty) {
      throw ArgumentError.value(binds, 'binds', 'binds must not be empty');
    }
    if (secure) {
      if (certificatePath == null || certificatePath.isEmpty) {
        throw ArgumentError.value(
          certificatePath,
          'certificatePath',
          'certificatePath is required for secure NativeHttpServer',
        );
      }
      if (keyPath == null || keyPath.isEmpty) {
        throw ArgumentError.value(
          keyPath,
          'keyPath',
          'keyPath is required for secure NativeHttpServer',
        );
      }
    }

    final requestController = StreamController<HttpRequest>();
    final connectionCounters = _ProxyConnectionCounters();
    final server = NativeHttpServer._(requestController, connectionCounters);
    final runtime = BridgeHttpRuntime(server._handleRequest);

    final internalShutdown = Completer<void>();
    if (shutdownSignal != null) {
      // ignore: discarded_futures
      shutdownSignal.whenComplete(() {
        if (!internalShutdown.isCompleted) {
          internalShutdown.complete();
        }
      });
    }

    try {
      for (var i = 0; i < binds.length; i++) {
        final bind = binds[i];
        final normalizedHost = _normalizeBindHost(bind.host, 'binds[$i].host');
        final running = await _startNativeProxy(
          host: normalizedHost,
          port: bind.port,
          secure: secure,
          echo: false,
          backlog: backlog,
          v6Only: v6Only,
          shared: shared,
          requestClientCertificate: requestClientCertificate,
          http3: http3,
          shutdownSignal: internalShutdown.future,
          tlsCertPath: certificatePath,
          tlsKeyPath: keyPath,
          tlsCertPassword: certificatePassword,
          installSignalHandlers: false,
          connectionCounters: connectionCounters,
          idleTimeoutProvider: () => server.idleTimeout,
          handleFrame: (frame) async =>
              _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
          handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
            await runtime.handleFrame(
              BridgeRequestFrame.decodePayload(payload),
            ),
          ),
          handleStream: runtime.handleStream,
        );
        final address = await _resolveInternetAddress(normalizedHost);
        server._bindings.add(
          _FfiHttpBinding(address: address, running: running),
        );
        server._runningBindingCount++;
        // ignore: discarded_futures
        running.done.whenComplete(() {
          if (!internalShutdown.isCompleted) {
            internalShutdown.complete();
          }
          server._completeIfStopped();
        });
      }
    } catch (error) {
      await server.close(force: true);
      rethrow;
    }

    return server;
  }

  final StreamController<HttpRequest> _requestController;
  final _ProxyConnectionCounters _connectionCounters;
  final List<_FfiHttpBinding> _bindings = <_FfiHttpBinding>[];
  final Completer<void> _stopped = Completer<void>();
  final _FfiSessionStore _sessions = _FfiSessionStore(
    timeout: const Duration(minutes: 20),
  );
  int _sessionTimeoutSeconds = 20 * 60;
  int _runningBindingCount = 0;
  bool _closed = false;

  static HttpHeaders _createDefaultResponseHeaders() {
    final headers = BridgeHttpResponse().headers;
    headers.contentType = ContentType.text;
    headers.set('x-frame-options', 'SAMEORIGIN');
    headers.set('x-content-type-options', 'nosniff');
    headers.set('x-xss-protection', '1; mode=block');
    return headers;
  }

  Future<void> _handleRequest(BridgeHttpRequest request) {
    if (_closed || _requestController.isClosed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      return request.response.close();
    }
    _applyRequestPolicies(request);
    _requestController.add(request);
    return request.response.done;
  }

  void _applyRequestPolicies(BridgeHttpRequest request) {
    request.setSessionFactory(
      () => _sessions.resolve(
        request: request,
        response: request.response,
        timeout: Duration(seconds: _sessionTimeoutSeconds),
      ),
    );
    final requestAcceptsGzip = _acceptsGzip(request);
    final response = request.response;
    if (response case BridgeHttpResponse()) {
      response.configureAutoCompression(
        enabled: autoCompress,
        requestAcceptsGzip: requestAcceptsGzip,
      );
    } else if (response case BridgeStreamingHttpResponse()) {
      response.configureAutoCompression(
        enabled: autoCompress,
        requestAcceptsGzip: requestAcceptsGzip,
      );
    }

    final responseHeaders = request.response.headers;
    defaultResponseHeaders.forEach((name, values) {
      responseHeaders.removeAll(name);
      for (final value in values) {
        responseHeaders.add(name, value);
      }
    });
    final serverHeader = this.serverHeader;
    if (serverHeader != null) {
      responseHeaders.set(HttpHeaders.serverHeader, serverHeader);
    }
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

bool _acceptsGzip(HttpRequest request) {
  final values = <String>[];
  request.headers.forEach((name, headerValues) {
    if (_equalsAsciiIgnoreCase(name, HttpHeaders.acceptEncodingHeader)) {
      values.addAll(headerValues);
    }
  });
  if (values.isEmpty) {
    return false;
  }
  for (final value in values) {
    final parts = value.split(',');
    for (final part in parts) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final semicolonIndex = token.indexOf(';');
      final encoding = semicolonIndex == -1
          ? token
          : token.substring(0, semicolonIndex).trim();
      if (!_equalsAsciiIgnoreCase(encoding, 'gzip')) {
        continue;
      }
      if (semicolonIndex == -1) {
        return true;
      }
      final parameters = token.substring(semicolonIndex + 1).split(';');
      var qValue = 1.0;
      for (final rawParameter in parameters) {
        final parameter = rawParameter.trim();
        if (parameter.isEmpty) {
          continue;
        }
        final equalsIndex = parameter.indexOf('=');
        if (equalsIndex == -1) {
          continue;
        }
        final name = parameter.substring(0, equalsIndex).trim();
        if (!_equalsAsciiIgnoreCase(name, 'q')) {
          continue;
        }
        qValue =
            double.tryParse(parameter.substring(equalsIndex + 1).trim()) ?? 1.0;
      }
      if (qValue > 0) {
        return true;
      }
    }
  }
  return false;
}

final class _FfiSessionStore {
  _FfiSessionStore({required Duration timeout}) : _timeout = timeout;

  static const String cookieName = 'DARTSESSID';

  final Map<String, _FfiSession> _sessions = <String, _FfiSession>{};
  Duration _timeout;
  int _nextId = 0;

  void setTimeout(Duration timeout) {
    _timeout = timeout;
    for (final session in _sessions.values) {
      session.timeout = timeout;
    }
  }

  HttpSession resolve({
    required BridgeHttpRequest request,
    required HttpResponse response,
    required Duration timeout,
  }) {
    if (_timeout != timeout) {
      setTimeout(timeout);
    }
    _pruneExpiredSessions();
    final cookieValue = _sessionCookieValue(request.cookies);
    _FfiSession? session;
    if (cookieValue != null) {
      session = _sessions[cookieValue];
    }
    if (session == null) {
      session = _createSession();
      _sessions[session.id] = session;
    } else {
      session.isNew = false;
      session.touch();
    }
    session.bindResponseCookie(
      response,
      secure: request.requestedUri.scheme == 'https',
    );
    return session;
  }

  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }

  _FfiSession _createSession() {
    final id = _nextSessionId();
    final session = _FfiSession(
      id: id,
      timeout: _timeout,
      onExpired: () {
        _sessions.remove(id);
      },
      onDestroyed: () {
        _sessions.remove(id);
      },
    );
    return session;
  }

  String _nextSessionId() {
    _nextId++;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '$micros-$_nextId';
  }

  String? _sessionCookieValue(List<Cookie> cookies) {
    for (final cookie in cookies) {
      if (_equalsAsciiIgnoreCase(cookie.name, cookieName)) {
        return cookie.value;
      }
    }
    return null;
  }

  void _pruneExpiredSessions() {
    if (_sessions.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final expiredIds = <String>[];
    _sessions.forEach((id, session) {
      if (session.expiresAt.isBefore(now)) {
        expiredIds.add(id);
      }
    });
    for (final id in expiredIds) {
      final session = _sessions.remove(id);
      session?.expire();
    }
  }
}

final class _FfiSession extends MapBase<dynamic, dynamic>
    implements HttpSession {
  _FfiSession({
    required this.id,
    required Duration timeout,
    required void Function() onExpired,
    required void Function() onDestroyed,
  }) : _timeout = timeout,
       _onExpired = onExpired,
       _onDestroyed = onDestroyed {
    _scheduleTimeout();
  }

  @override
  final String id;

  @override
  bool isNew = true;

  final Map<String, dynamic> _data = <String, dynamic>{};
  final void Function() _onExpired;
  final void Function() _onDestroyed;
  final Set<HttpResponse> _boundResponses = <HttpResponse>{};
  void Function()? _timeoutCallback;

  Timer? _timer;
  bool _destroyed = false;
  Duration _timeout;
  DateTime _expiresAt = DateTime.now();

  DateTime get expiresAt => _expiresAt;

  set timeout(Duration value) {
    _timeout = value;
    if (!_destroyed) {
      _scheduleTimeout();
    }
  }

  @override
  set onTimeout(void Function() callback) {
    _timeoutCallback = callback;
  }

  void touch() {
    if (_destroyed) {
      return;
    }
    _scheduleTimeout();
  }

  void bindResponseCookie(HttpResponse response, {required bool secure}) {
    if (_destroyed) {
      _appendExpiredSessionCookie(response, secure: secure);
      return;
    }
    _boundResponses.add(response);
    response.cookies.add(
      Cookie(_FfiSessionStore.cookieName, id)
        ..path = '/'
        ..httpOnly = true
        ..secure = secure
        ..maxAge = _timeout.inSeconds,
    );
  }

  void expire() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _timer?.cancel();
    _timer = null;
    _data.clear();
    _timeoutCallback?.call();
    for (final response in _boundResponses) {
      _appendExpiredSessionCookie(response, secure: false);
    }
    _boundResponses.clear();
    _onExpired();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _timer?.cancel();
    _timer = null;
    _data.clear();
    for (final response in _boundResponses) {
      _appendExpiredSessionCookie(response, secure: false);
    }
    _boundResponses.clear();
    _onDestroyed();
  }

  @override
  dynamic operator [](Object? key) => key is String ? _data[key] : null;

  @override
  void operator []=(Object? key, dynamic value) {
    if (_destroyed) {
      throw StateError('Session is destroyed');
    }
    if (key is! String) {
      throw ArgumentError('Session keys must be strings');
    }
    _data[key] = value;
  }

  @override
  void clear() => _data.clear();

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  dynamic remove(Object? key) => key is String ? _data.remove(key) : null;

  void _scheduleTimeout() {
    _expiresAt = DateTime.now().add(_timeout);
    _timer?.cancel();
    if (_timeout <= Duration.zero) {
      _timer = Timer(Duration.zero, expire);
      return;
    }
    _timer = Timer(_timeout, expire);
  }

  void _appendExpiredSessionCookie(
    HttpResponse response, {
    required bool secure,
  }) {
    response.cookies.add(
      Cookie(_FfiSessionStore.cookieName, '')
        ..path = '/'
        ..httpOnly = true
        ..secure = secure
        ..maxAge = 0
        ..expires = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
