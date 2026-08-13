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
        denoCapabilities;
export 'src/runtime/lifecycle.dart';
export 'src/listener/js_listener.dart' show serveJsListener;

/// Starts a Routed application on Deno.
Future<ServerHandle> serveDeno(
  Engine engine, {
  String host = '0.0.0.0',
  int port = 0,
}) {
  const info = RoutedNodeRuntimeInfo(
    runtime: RoutedNodeRuntime.deno,
    capabilities: denoCapabilities,
  );
  return serveJsListener('Deno', engine, host: host, port: port, info: info);
}
