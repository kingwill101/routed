import 'package:routed_core/routed_core.dart';

import 'node_views.dart';
import 'runtime/lifecycle.dart';
import 'runtime/runtime.dart';

/// Maps a Node [NodeIncomingView] into a core [PortableRequest].
PortableRequest portableRequestFromNode(
  NodeIncomingView incoming, {
  Uri? baseUri,
  RoutedNodeContext? hostContext,
}) {
  final rawUrl = incoming.url.isEmpty ? '/' : incoming.url;
  final base = baseUri ?? Uri(scheme: 'http', host: 'localhost');
  final uri = base.resolve(rawUrl);

  final headers = PortableHeaders();
  incoming.rawHeaders.forEach((name, value) {
    if (value == null) return;
    if (value is List) {
      headers.setAll(
        name,
        value.map((e) => e.toString()).toList(growable: false),
      );
    } else {
      headers.set(name, value.toString());
    }
  });

  return PortableRequest(
    method: incoming.method.isEmpty ? 'GET' : incoming.method,
    uri: uri,
    headers: headers,
    body: incoming.body,
    remoteAddress: incoming.remoteAddress,
    hostContext: hostContext,
  );
}

/// Writes a core [PortableResponse] to a Node [NodeServerResponseView].
Future<void> writePortableResponseToNode(
  PortableResponse source,
  NodeServerResponseView target,
) async {
  final flat = <String, Object>{};
  source.headers.forEach((name, values) {
    if (name.toLowerCase() == 'set-cookie') {
      flat[name] = values;
    } else if (values.length == 1) {
      flat[name] = values.first;
    } else {
      flat[name] = values.join(', ');
    }
  });

  target.writeHead(source.statusCode, flat);

  await for (final chunk in source.body) {
    if (chunk.isNotEmpty) target.write(chunk);
  }

  if (!target.finished) {
    target.end();
  }
}

/// Runs [engine.handlePortable] for one Node exchange.
Future<void> dispatchNodeExchange(
  Engine engine,
  NodeIncomingView incoming,
  NodeServerResponseView outgoing, {
  Uri? baseUri,
  RoutedNodeContext? hostContext,
}) async {
  final info =
      hostContext?.info ??
      const RoutedNodeRuntimeInfo(
        runtime: RoutedNodeRuntime.node,
        capabilities: nodeCapabilities,
      );
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.requestStarted,
      info: info,
    ),
  );
  try {
    final portableIn = portableRequestFromNode(
      incoming,
      baseUri: baseUri,
      hostContext: hostContext,
    );
    final portableOut = await engine.handlePortable(portableIn);
    await writePortableResponseToNode(portableOut, outgoing);
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.requestFinished,
        info: info,
      ),
    );
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
