/// Bun listener adapters and runtime metadata for Routed applications.
///
/// {@canonicalFor js_listener.serveJsListener}
library;

import 'package:routed_core/routed_core.dart';

import 'src/listener/js_listener.dart';
import 'src/runtime/runtime.dart';

export 'src/runtime/runtime.dart'
    show
        RoutedNodeCapabilities,
        RoutedNodeContext,
        RoutedNodeEntryModel,
        RoutedNodeExtension,
        RoutedNodeRuntime,
        RoutedNodeRuntimeInfo,
        bunCapabilities;
export 'src/runtime/lifecycle.dart';
export 'src/listener/js_listener.dart' show serveJsListener;

/// Starts a Routed application on Bun.
Future<ServerHandle> serveBun(
  Engine engine, {
  String host = '0.0.0.0',
  int port = 0,
}) {
  const info = RoutedNodeRuntimeInfo(
    runtime: RoutedNodeRuntime.bun,
    capabilities: bunCapabilities,
  );
  return serveJsListener('Bun', engine, host: host, port: port, info: info);
}
