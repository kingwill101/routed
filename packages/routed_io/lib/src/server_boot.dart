import 'package:routed_core/routed_core.dart';

import 'package:routed_io/src/io_server_transport.dart';

/// Boots a Routed [engine] using the `dart:io` HTTP server transport.
///
/// Prefer this over `Engine.serve` for new code so bind/listen lives outside
/// `routed_core`. Default: native [Engine.handleConnection] fast path.
/// Set [portableEdge] to use `dispatchIoExchange` / `Engine.handlePortable`.
///
/// Returns a [ServerHandle] that can close the listener.
Future<ServerHandle> serveIo(
  Engine engine, {
  String host = '127.0.0.1',
  int? port,
  bool echo = true,
  bool portableEdge = false,
}) async {
  if (engine.config.features.enableProxySupport) {
    await engine.config.ensureTrustedProxiesParsed();
  }
  if (echo) {
    try {
      engine.printRoutes();
    } on Object catch (_) {}
  }

  final transport = IoServerTransport(echo: echo, portableEdge: portableEdge);
  return transport.serve(
    engine,
    ServerOptions(host: host, port: port ?? 0, shared: true),
  );
}

/// Boots a Routed [engine] using the `dart:io` HTTPS server transport.
///
/// TLS bind still delegates to `Engine.serveSecure` until TLS options are
/// folded into [IoServerTransport].
Future<void> serveSecureIo(
  Engine engine, {
  String address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  bool? v6Only,
  bool? requestClientCertificate,
  bool? shared,
}) {
  return engine.serveSecure(
    address: address,
    port: port,
    certificatePath: certificatePath,
    keyPath: keyPath,
    certificatePassword: certificatePassword,
    v6Only: v6Only,
    requestClientCertificate: requestClientCertificate,
    shared: shared,
  );
}
