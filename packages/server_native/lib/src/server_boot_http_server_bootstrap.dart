part of 'server_boot.dart';

/// Runtime bind metadata for one active [NativeHttpServer] listener.
final class _NativeHttpBinding {
  _NativeHttpBinding({required this.address, required this.running});

  final InternetAddress address;
  final _RunningProxy running;
}

/// Creates the default response-headers template used by [NativeHttpServer].
HttpHeaders _createNativeHttpDefaultResponseHeaders() {
  final headers = BridgeHttpResponse(
    connectionInfo: BridgeConnectionInfo(
      remoteAddress: InternetAddress.loopbackIPv4,
      remotePort: 0,
      localPort: 0,
    ),
  ).headers;
  headers.contentType = ContentType.text;
  headers.set('x-frame-options', 'SAMEORIGIN');
  headers.set('x-content-type-options', 'nosniff');
  headers.set('x-xss-protection', '1; mode=block');
  return headers;
}

/// Boots [NativeHttpServer.bind] with support for `"localhost"` and `"any"`.
Future<NativeHttpServer> _nativeHttpServerBind(
  Object address,
  int port, {
  required int backlog,
  required bool v6Only,
  required bool shared,
  required bool http2,
  required bool http3,
  required bool nativeCallback,
  Future<void>? shutdownSignal,
}) async {
  final normalizedAddress = _normalizeBindHost(address, 'address');
  if (normalizedAddress == 'localhost') {
    return _nativeHttpServerLoopback(
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      http2: http2,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }
  if (normalizedAddress == 'any') {
    return _startNativeHttpServer(
      binds: <NativeServerBind>[
        NativeServerBind(host: await _anyHost(), port: port),
      ],
      secure: false,
      backlog: backlog,
      v6Only: v6Only,
      requestClientCertificate: false,
      shared: shared,
      http2: http2,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }
  return _startNativeHttpServer(
    binds: <NativeServerBind>[
      NativeServerBind(host: normalizedAddress, port: port),
    ],
    secure: false,
    backlog: backlog,
    v6Only: v6Only,
    requestClientCertificate: false,
    shared: shared,
    http2: http2,
    http3: http3,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
  );
}

/// Boots [NativeHttpServer.loopback] listeners.
Future<NativeHttpServer> _nativeHttpServerLoopback(
  int port, {
  required int backlog,
  required bool v6Only,
  required bool shared,
  required bool http2,
  required bool http3,
  required bool nativeCallback,
  Future<void>? shutdownSignal,
}) async {
  return _startNativeLoopbackHttpServer(
    port: port,
    secure: false,
    backlog: backlog,
    v6Only: v6Only,
    requestClientCertificate: false,
    shared: shared,
    http2: http2,
    http3: http3,
    nativeCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
  );
}

/// Boots [NativeHttpServer.bindSecure] with support for `"localhost"`/`"any"`.
Future<NativeHttpServer> _nativeHttpServerBindSecure(
  Object address,
  int port, {
  required String certificatePath,
  required String keyPath,
  String? certificatePassword,
  required int backlog,
  required bool v6Only,
  required bool requestClientCertificate,
  required bool shared,
  required bool http2,
  required bool http3,
  required bool nativeCallback,
  Future<void>? shutdownSignal,
}) async {
  final normalizedAddress = _normalizeBindHost(address, 'address');
  if (normalizedAddress == 'localhost') {
    return _nativeHttpServerLoopbackSecure(
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
  }
  if (normalizedAddress == 'any') {
    return _startNativeHttpServer(
      binds: <NativeServerBind>[
        NativeServerBind(host: await _anyHost(), port: port),
      ],
      secure: true,
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
  }
  return _startNativeHttpServer(
    binds: <NativeServerBind>[
      NativeServerBind(host: normalizedAddress, port: port),
    ],
    secure: true,
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
}

/// Boots [NativeHttpServer.loopbackSecure] listeners.
Future<NativeHttpServer> _nativeHttpServerLoopbackSecure(
  int port, {
  required String certificatePath,
  required String keyPath,
  String? certificatePassword,
  required int backlog,
  required bool v6Only,
  required bool requestClientCertificate,
  required bool shared,
  required bool http2,
  required bool http3,
  required bool nativeCallback,
  Future<void>? shutdownSignal,
}) async {
  return _startNativeLoopbackHttpServer(
    port: port,
    secure: true,
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
}

/// Starts loopback listeners with retry behavior for dual-stack ephemeral port
/// collisions.
///
/// On some systems a port selected on IPv4 may race with IPv6 availability even
/// after pre-reservation. This mirrors `http_multi_server` semantics by
/// retrying ephemeral loopback startup when a transient address-in-use bind
/// error is encountered.
Future<NativeHttpServer> _startNativeLoopbackHttpServer({
  required int port,
  required bool secure,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  required int backlog,
  required bool v6Only,
  required bool requestClientCertificate,
  required bool shared,
  required bool http2,
  required bool http3,
  required bool nativeCallback,
  Future<void>? shutdownSignal,
}) async {
  final supportsV4 = await _supportsIPv4;
  final supportsV6 = await _supportsIPv6;
  final retryEligible = port == 0 && supportsV4 && supportsV6;
  const maxRetries = 5;
  var attempt = 0;

  while (true) {
    try {
      return await _startNativeHttpServer(
        binds: await _loopbackBinds(port),
        secure: secure,
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
    } catch (error) {
      if (!retryEligible ||
          attempt >= maxRetries ||
          !_isAddressInUseBindFailure(error)) {
        rethrow;
      }
      attempt++;
      _nativeVerboseLog(
        '[server_native] loopback dual-stack bind collision; retrying '
        'ephemeral port startup (attempt $attempt/$maxRetries).',
      );
    }
  }
}

/// Starts the underlying transport listeners and wires them into one server.
Future<NativeHttpServer> _startNativeHttpServer({
  required List<NativeServerBind> binds,
  required bool secure,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  required int backlog,
  required bool v6Only,
  required bool requestClientCertificate,
  required bool shared,
  required bool http2,
  required bool http3,
  required bool nativeCallback,
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
        http2: http2,
        http3: http3,
        nativeDirectCallback: nativeCallback,
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
          await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
        ),
        handleStream: runtime.handleStream,
      );
      final address = await _resolveInternetAddress(normalizedHost);
      server._bindings.add(
        _NativeHttpBinding(address: address, running: running),
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
  } catch (_) {
    await server.close(force: true);
    rethrow;
  }

  return server;
}
