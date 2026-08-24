import 'package:routed_core/routed_core.dart';

import 'node_runtime.dart' as runtime;

/// A `ServerTransport` using Node.js `http.createServer`.
///
/// On the Dart VM this throws `UnsupportedError` (see `serveNode`).
/// When compiled for a JavaScript/Node host, binds and dispatches each
/// request through `Engine.handleConnection` via `NodeHttpConnection`.
final class NodeServerTransport implements ServerTransport {
  /// Creates a NodeServerTransport value.
  const NodeServerTransport({this.echo = false});

  /// The echo value.
  final bool echo;

  @override
  Future<ServerHandle> serve(Engine engine, ServerOptions options) {
    return runtime.bindNodeHttp(engine, options, echo: echo);
  }
}
