part of 'server_boot.dart';

/// Listener binding config for FFI server boot helpers.
///
/// Use this with [serveNativeMulti] and [serveSecureNativeMulti] to expose one
/// logical server runtime on multiple host/port listeners.
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
  ///
  /// Set [nativeCallback] to `true` (default) to use native request callbacks
  /// instead of bridge-socket transport. Provide [shutdownSignal] to terminate
  /// the server without OS signals.
  static Future<void> loopback(
    BridgeHttpHandler handler,
    int port, {
    bool echo = true,
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http2 = true,
    bool http3 = true,
    bool nativeCallback = true,
    Future<void>? shutdownSignal,
  }) async {
    final binds = await _loopbackBinds(port);
    await serveNativeMulti(
      handler,
      binds: binds,
      echo: echo,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      http2: http2,
      http3: http3,
      nativeCallback: nativeCallback,
      shutdownSignal: shutdownSignal,
    );
  }

  /// Boots server_native TLS transport on all available loopback interfaces.
  ///
  /// For `port == 0`, a shared ephemeral port is reserved first so both
  /// loopback listeners use the same port.
  ///
  /// Set [nativeCallback] to `true` (default) to use native request callbacks
  /// instead of bridge-socket transport. Provide [shutdownSignal] to terminate
  /// the server without OS signals.
  static Future<void> loopbackSecure(
    BridgeHttpHandler handler,
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
  }) async {
    final binds = await _loopbackBinds(port);
    await serveSecureNativeMulti(
      handler,
      binds: binds,
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

  /// Boots server_native transport with `HttpMultiServer` address semantics.
  ///
  /// For `'localhost'` behaves like [loopback].
  ///
  /// For `'any'` listens on [InternetAddress.anyIPv6] when IPv6 is available,
  /// else [InternetAddress.anyIPv4].
  ///
  /// Set [nativeCallback] to `true` (default) to use native request callbacks
  /// instead of bridge-socket transport. Provide [shutdownSignal] to terminate
  /// the server without OS signals.
  static Future<void> bind(
    BridgeHttpHandler handler,
    Object address,
    int port, {
    bool echo = true,
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool http2 = true,
    bool http3 = true,
    bool nativeCallback = true,
    Future<void>? shutdownSignal,
  }) async {
    final normalized = _normalizeBindHost(address, 'address');
    if (normalized == 'localhost') {
      return loopback(
        handler,
        port,
        echo: echo,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        http2: http2,
        http3: http3,
        nativeCallback: nativeCallback,
        shutdownSignal: shutdownSignal,
      );
    }
    if (normalized == 'any') {
      final host = await _anyHost();
      return serveNative(
        handler,
        host: host,
        port: port,
        echo: echo,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        http2: http2,
        http3: http3,
        nativeCallback: nativeCallback,
        shutdownSignal: shutdownSignal,
      );
    }
    return serveNative(
      handler,
      host: normalized,
      port: port,
      echo: echo,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
      http2: http2,
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
  ///
  /// Set [nativeCallback] to `true` (default) to use native request callbacks
  /// instead of bridge-socket transport. Provide [shutdownSignal] to terminate
  /// the server without OS signals.
  static Future<void> bindSecure(
    BridgeHttpHandler handler,
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
  }) async {
    final normalized = _normalizeBindHost(address, 'address');
    if (normalized == 'localhost') {
      return loopbackSecure(
        handler,
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
    if (normalized == 'any') {
      final host = await _anyHost();
      return serveSecureNative(
        handler,
        address: host,
        port: port,
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
    return serveSecureNative(
      handler,
      address: normalized,
      port: port,
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
}
