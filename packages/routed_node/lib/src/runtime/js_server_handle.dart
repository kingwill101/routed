import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';

import 'lifecycle.dart';
import 'runtime.dart';

/// Server handle for a JavaScript-hosted listener.
final class JsServerHandle implements ServerHandle {
  /// Creates a handle for a JavaScript-hosted listener.
  JsServerHandle({
    required this.server,
    required this.engine,
    required this.info,
    required this.host,
    required this.port,
    this.closeSockets,
    this.waitForSockets,
  });

  /// The host-native server object controlled by this handle.
  final JSObject server;

  /// The Routed engine served by the listener.
  final Engine engine;

  /// Runtime metadata used for lifecycle events.
  final RoutedNodeRuntimeInfo info;
  @override
  final String host;
  @override
  final int port;

  /// Closes host-managed sockets before the server stops, when provided.
  final void Function()? closeSockets;

  /// Completes after host-managed sockets have stopped, when provided.
  final Future<void> Function()? waitForSockets;
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

    closeSockets?.call();

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

    if (waitForSockets != null) await waitForSockets!();

    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.stopped,
        info: info,
      ),
    );
  }
}

/// Publishes a lifecycle event for a requested host boot.
void publishHostBootRequested(Engine engine, RoutedNodeRuntimeInfo info) {
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.bootRequested,
      info: info,
    ),
  );
}

/// Publishes a lifecycle event after a host starts accepting requests.
void publishHostReady(Engine engine, RoutedNodeRuntimeInfo info) {
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(phase: RoutedNodeLifecyclePhase.ready, info: info),
  );
}
