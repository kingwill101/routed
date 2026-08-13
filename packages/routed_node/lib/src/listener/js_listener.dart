@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';

import '../runtime/js_server_handle.dart';
import '../runtime/runtime.dart';
import 'listener_views.dart';

/// Starts a JavaScript listener using the supplied host server factory.
Future<ServerHandle> serveJsListener(
  String runtime,
  Engine engine, {
  required String host,
  required int port,
  required RoutedNodeRuntimeInfo info,
}) async {
  await engine.initialize();
  final server = await createHostServer(
    runtime,
    engine,
    host: host,
    port: port,
  );
  final actualPort = _readPort(server) ?? port;
  publishHostReady(engine, info);
  return JsServerHandle(
    server: server,
    engine: engine,
    info: info,
    host: host,
    port: actualPort,
  );
}

Future<JSObject> createHostServer(
  String runtime,
  Engine engine, {
  required String host,
  required int port,
}) async {
  final server = await hostCreateServer(
    runtime,
    engine,
    host: host,
    port: port,
  );
  return server;
}

int? _readPort(JSObject server) {
  final value = server.getProperty('port'.toJS);
  return value != null && value.isA<JSNumber>()
      ? (value as JSNumber).toDartInt
      : null;
}
