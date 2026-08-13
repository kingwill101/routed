import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';

import 'lifecycle.dart';
import 'runtime.dart';

/// Server handle for a JavaScript-hosted listener.
final class JsServerHandle implements ServerHandle {
  JsServerHandle({
    required this.server,
    required this.engine,
    required this.info,
    required this.host,
    required this.port,
  });

  final JSObject server;
  final Engine engine;
  final RoutedNodeRuntimeInfo info;
  @override
  final String host;
  @override
  final int port;
  bool _closed = false;

  @override
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.shutdownRequested,
        info: info,
      ),
    );

    final stop = server.getProperty('stop'.toJS);
    if (stop != null && stop.isA<JSFunction>()) {
      final result = (stop as JSFunction).callAsFunction(server, force.toJS);
      if (result != null && result.isA<JSPromise<JSAny?>>()) {
        await (result as JSPromise<JSAny?>).toDart;
      }
    } else {
      final close = server.getProperty('close'.toJS);
      if (close != null && close.isA<JSFunction>()) {
        final result = (close as JSFunction).callAsFunction(server);
        if (result != null && result.isA<JSPromise<JSAny?>>()) {
          await (result as JSPromise<JSAny?>).toDart;
        }
      }
    }

    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.stopped,
        info: info,
      ),
    );
  }
}

void publishHostBootRequested(Engine engine, RoutedNodeRuntimeInfo info) {
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.bootRequested,
      info: info,
    ),
  );
}

void publishHostReady(Engine engine, RoutedNodeRuntimeInfo info) {
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(phase: RoutedNodeLifecyclePhase.ready, info: info),
  );
}
