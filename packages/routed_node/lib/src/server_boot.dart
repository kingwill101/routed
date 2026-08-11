import 'package:routed_core/routed_core.dart';

import 'node_server_transport.dart';

/// Boots a Routed [engine] using the Node.js HTTP server transport.
///
/// Prefer this over [Engine.serve] when targeting Node. Uses
/// [NodeServerTransport] + [Engine.handleConnection].
///
/// **Runtime note:** bind/listen only works when this package is compiled for
/// a JavaScript/Node host. On the Dart VM, adapters and
/// `Engine.handleConnection` still work with fakes; [serveNode] throws
/// [UnsupportedError] pointing at `package:routed_io` for VM hosting.
Future<ServerHandle> serveNode(
  Engine engine, {
  String host = '127.0.0.1',
  int? port,
  bool echo = true,
}) async {
  if (engine.config.features.enableProxySupport) {
    await engine.config.ensureTrustedProxiesParsed();
  }
  if (echo) {
    try {
      engine.printRoutes();
    } catch (_) {}
  }

  final transport = NodeServerTransport(echo: echo);
  return transport.serve(
    engine,
    ServerOptions(host: host, port: port ?? 0, shared: false),
  );
}
