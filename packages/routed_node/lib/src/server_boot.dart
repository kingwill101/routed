import 'package:routed_core/routed_core.dart';

import 'node_server_transport.dart';
import 'node_runtime.dart' as node_runtime;
import 'runtime/lifecycle.dart';
import 'runtime/runtime.dart';

/// Boots a Routed `engine` using the Node.js HTTP server transport.
///
/// Prefer this over `Engine.serve` when targeting Node. Uses
/// `NodeServerTransport` + `Engine.handleConnection`.
///
/// **Runtime note:** bind/listen only works when this package is compiled for
/// a JavaScript/Node host. On the Dart VM, adapters and
/// `Engine.handleConnection` still work with fakes; `serveNode` throws
/// `UnsupportedError` pointing at `package:routed_io` for VM hosting.
Future<ServerHandle> serveNode(
  Engine engine, {
  String host = '127.0.0.1',
  int? port,
  bool echo = true,
}) async {
  node_runtime.keepNodeEventLoopAlive();
  final info = RoutedNodeRuntimeInfo(
    runtime: RoutedNodeRuntime.node,
    capabilities: nodeCapabilities,
  );
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.bootRequested,
      info: info,
    ),
  );

  if (engine.config.features.enableProxySupport) {
    await engine.config.ensureTrustedProxiesParsed();
  }
  if (echo) {
    try {
      engine.printRoutes();
    } catch (_) {}
  }

  final transport = NodeServerTransport(echo: echo);
  try {
    final handle = await transport.serve(
      engine,
      ServerOptions(host: host, port: port ?? 0, shared: false),
    );
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.ready,
        info: info,
      ),
    );
    return _LifecycleServerHandle(handle, engine, info);
  } catch (error, stackTrace) {
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.requestFailed,
        info: info,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    rethrow;
  }
}

final class _LifecycleServerHandle implements ServerHandle {
  _LifecycleServerHandle(this._delegate, this._engine, this._info);

  final ServerHandle _delegate;
  final Engine _engine;
  final RoutedNodeRuntimeInfo _info;
  bool _closed = false;

  @override
  String get host => _delegate.host;

  @override
  int get port => _delegate.port;

  @override
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;
    publishRoutedNodeLifecycle(
      _engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.shutdownRequested,
        info: _info,
      ),
    );
    await _delegate.close(force: force);
    publishRoutedNodeLifecycle(
      _engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.stopped,
        info: _info,
      ),
    );
  }
}
