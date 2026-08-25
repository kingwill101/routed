import 'package:routed_core/routed_core.dart';

import 'package:routed_io/src/io_portable.dart' show dispatchIoExchange;
import 'package:routed_io/src/io_server_transport.dart';

/// Starts a Routed [engine] using the `dart:io` HTTP server transport.
///
/// This is the recommended process-hosted entry point because binding and
/// listening stay in `routed_io` while the engine remains host-neutral. The
/// default path uses [Engine.handleConnection], retaining native request and
/// response access for WebSockets and progressive writes. Set [portableEdge]
/// to route requests through [dispatchIoExchange] and [Engine.handlePortable]
/// for value-edge parity testing.
///
/// The engine is initialized by the transport before binding. Returns a
/// [ServerHandle] that owns the listener; call [ServerHandle.close] during
/// shutdown.
///
/// [host] defaults to loopback for a local development server. A [port] of
/// `null` selects an ephemeral port, which is useful for tests. When [echo] is
/// true, the route table and bound address are printed during startup.
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

/// Starts a Routed [engine] using the `dart:io` HTTPS server transport.
///
/// TLS binding currently delegates to `Engine.serveSecure`. [address] and
/// [port] select the listening endpoint; [certificatePath] and [keyPath]
/// identify the certificate and private-key files used by the Dart VM. The
/// optional TLS and socket arguments are passed through unchanged.
///
/// Returns when the underlying secure server has completed its serve
/// operation. Use [serveIo] when you need the [ServerHandle] returned by the
/// transport-backed HTTP path.
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
