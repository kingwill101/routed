part of 'server_boot.dart';

/// Boots the Rust-native transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// {@macro server_native_serve_handler_example}
Future<void> serveNative(
  BridgeHttpHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) {
  final runtime = BridgeHttpRuntime(handler);
  final normalizedHost = _normalizeBindHost(host, 'host');
  return _serveWithNativeProxy(
    host: normalizedHost,
    port: port ?? 0,
    secure: false,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: false,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native TLS transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// This requires PEM certificate and key files.
///
/// {@macro server_native_serve_handler_example}
Future<void> serveSecureNative(
  BridgeHttpHandler handler, {
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNative',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNative',
    );
  }

  final runtime = BridgeHttpRuntime(handler);
  final normalizedAddress = _normalizeBindHost(address, 'address');
  return _serveWithNativeProxy(
    host: normalizedAddress,
    port: port,
    secure: true,
    echo: false,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots one logical handler across multiple Rust-native listeners.
///
/// Similar to `http_multi_server`, this runs one handler behind several bind
/// addresses. The only per-listener difference is host/port binding.
///
/// {@macro server_native_multi_bind_example}
Future<void> serveNativeMulti(
  BridgeHttpHandler handler, {
  required List<NativeServerBind> binds,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) async {
  if (binds.isEmpty) {
    throw ArgumentError.value(binds, 'binds', 'binds must not be empty');
  }

  final runtime = BridgeHttpRuntime(handler);
  final internalShutdown = Completer<void>();
  if (shutdownSignal != null) {
    // ignore: discarded_futures
    shutdownSignal.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  final futures = <Future<void>>[];
  for (var i = 0; i < binds.length; i++) {
    final bind = binds[i];
    final normalizedHost = _normalizeBindHost(bind.host, 'binds[$i].host');
    final future = _serveWithNativeProxy(
      host: normalizedHost,
      port: bind.port,
      secure: false,
      echo: echo,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      requestClientCertificate: false,
      http2: http2,
      http3: http3,
      nativeDirectCallback: nativeCallback,
      shutdownSignal: internalShutdown.future,
      handleFrame: (frame) async =>
          _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
      handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
        await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
      ),
      handleStream: runtime.handleStream,
    );
    futures.add(future);
    // Any listener completion (error or normal) should stop all listeners.
    // ignore: discarded_futures
    future.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  await Future.wait(futures);
}

/// Boots one logical handler across multiple Rust-native TLS listeners.
///
/// {@macro server_native_multi_bind_example}
Future<void> serveSecureNativeMulti(
  BridgeHttpHandler handler, {
  required List<NativeServerBind> binds,
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
}) async {
  if (binds.isEmpty) {
    throw ArgumentError.value(binds, 'binds', 'binds must not be empty');
  }
  if (certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNativeMulti',
    );
  }
  if (keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNativeMulti',
    );
  }

  final runtime = BridgeHttpRuntime(handler);
  final internalShutdown = Completer<void>();
  if (shutdownSignal != null) {
    // ignore: discarded_futures
    shutdownSignal.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  final futures = <Future<void>>[];
  for (var i = 0; i < binds.length; i++) {
    final bind = binds[i];
    final normalizedHost = _normalizeBindHost(bind.host, 'binds[$i].host');
    final future = _serveWithNativeProxy(
      host: normalizedHost,
      port: bind.port,
      secure: true,
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
      handleFrame: (frame) async =>
          _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
      handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
        await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
      ),
      handleStream: runtime.handleStream,
    );
    futures.add(future);
    // Any listener completion (error or normal) should stop all listeners.
    // ignore: discarded_futures
    future.whenComplete(() {
      if (!internalShutdown.isCompleted) {
        internalShutdown.complete();
      }
    });
  }

  await Future.wait(futures);
}

/// Boots the Rust-native transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// [nativeCallback] defaults to `true`, which bypasses the bridge socket and
/// delivers requests through the native callback transport while keeping
/// `HttpRequest`/`HttpResponse` compatibility.
/// Set [nativeCallback] to `false` to use bridge socket transport.
///
/// {@macro server_native_serve_http_handler_example}
Future<void> serveNativeHttp(
  BridgeHttpHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) {
  final runtime = BridgeHttpRuntime(handler);
  final normalizedHost = _normalizeBindHost(host, 'host');
  return _serveWithNativeProxy(
    host: normalizedHost,
    port: port ?? 0,
    secure: false,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: false,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native TLS transport and dispatches `HttpRequest` objects to
/// [handler], similar to listening on `dart:io` `HttpServer`.
///
/// [nativeCallback] defaults to `true`, which bypasses the bridge socket and
/// delivers requests through the native callback transport while keeping
/// `HttpRequest`/`HttpResponse` compatibility.
/// Set [nativeCallback] to `false` to use bridge socket transport.
///
/// {@macro server_native_serve_http_handler_example}
Future<void> serveSecureNativeHttp(
  BridgeHttpHandler handler, {
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeCallback = true,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNativeHttp',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNativeHttp',
    );
  }

  final runtime = BridgeHttpRuntime(handler);
  final normalizedAddress = _normalizeBindHost(address, 'address');
  return _serveWithNativeProxy(
    host: normalizedAddress,
    port: port,
    secure: true,
    echo: false,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeCallback,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: (frame) async =>
        _BridgeHandleFrameResult.frame(await runtime.handleFrame(frame)),
    handlePayload: (payload) async => _BridgeHandleFrameResult.frame(
      await runtime.handleFrame(BridgeRequestFrame.decodePayload(payload)),
    ),
    handleStream: runtime.handleStream,
  );
}

/// Boots the Rust-native transport and dispatches requests directly to [handler]
/// without `HttpRequest`/`HttpResponse` wrapper allocation.
///
/// {@macro server_native_direct_handler_example}
Future<void> serveNativeDirect(
  NativeDirectHandler handler, {
  Object host = '127.0.0.1',
  int? port,
  bool echo = true,
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeDirect = false,
  Future<void>? shutdownSignal,
}) {
  final normalizedHost = _normalizeBindHost(host, 'host');
  return _serveWithNativeProxy(
    host: normalizedHost,
    port: port ?? 0,
    secure: false,
    echo: echo,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: false,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeDirect,
    shutdownSignal: shutdownSignal,
    handleFrame: (frame) => _handleDirectFrame(handler, frame),
    handlePayload: (payload) => _handleDirectPayload(handler, payload),
    handleStream:
        ({
          required frame,
          required bodyStream,
          required onResponseStart,
          required onResponseChunk,
        }) => _handleDirectStream(
          handler,
          frame: frame,
          bodyStream: bodyStream,
          onResponseStart: onResponseStart,
          onResponseChunk: onResponseChunk,
        ),
  );
}

/// Boots the Rust-native TLS transport and dispatches requests directly to
/// [handler] without `HttpRequest`/`HttpResponse` wrapper allocation.
///
/// {@macro server_native_direct_handler_example}
Future<void> serveSecureNativeDirect(
  NativeDirectHandler handler, {
  Object address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool shared = false,
  bool http2 = true,
  bool http3 = true,
  bool nativeDirect = false,
  Future<void>? shutdownSignal,
}) {
  if (certificatePath == null || certificatePath.isEmpty) {
    throw ArgumentError.value(
      certificatePath,
      'certificatePath',
      'certificatePath is required for serveSecureNativeDirect',
    );
  }
  if (keyPath == null || keyPath.isEmpty) {
    throw ArgumentError.value(
      keyPath,
      'keyPath',
      'keyPath is required for serveSecureNativeDirect',
    );
  }

  final normalizedAddress = _normalizeBindHost(address, 'address');
  return _serveWithNativeProxy(
    host: normalizedAddress,
    port: port,
    secure: true,
    echo: false,
    backlog: backlog,
    v6Only: v6Only,
    shared: shared,
    requestClientCertificate: requestClientCertificate,
    http2: http2,
    http3: http3,
    nativeDirectCallback: nativeDirect,
    shutdownSignal: shutdownSignal,
    tlsCertPath: certificatePath,
    tlsKeyPath: keyPath,
    tlsCertPassword: certificatePassword,
    handleFrame: (frame) => _handleDirectFrame(handler, frame),
    handlePayload: (payload) => _handleDirectPayload(handler, payload),
    handleStream:
        ({
          required frame,
          required bodyStream,
          required onResponseStart,
          required onResponseChunk,
        }) => _handleDirectStream(
          handler,
          frame: frame,
          bodyStream: bodyStream,
          onResponseStart: onResponseStart,
          onResponseChunk: onResponseChunk,
        ),
  );
}
