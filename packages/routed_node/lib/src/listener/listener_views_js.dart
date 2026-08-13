@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';
import 'package:web/web.dart' as web;

import '../fetch/fetch_entry_js.dart';
import '../runtime/runtime.dart';

Future<JSObject> hostCreateServer(
  String runtime,
  Engine engine, {
  required String host,
  required int port,
}) async {
  final info = RoutedNodeRuntimeInfo(
    runtime: runtime == 'Bun' ? RoutedNodeRuntime.bun : RoutedNodeRuntime.deno,
    capabilities: runtime == 'Bun' ? bunCapabilities : denoCapabilities,
  );

  final callback = ((JSAny request) {
    return handleNativeFetch(engine, info, web.Request(request)).toJS;
  }).toJS;

  final global = globalContext;
  final hostObject = global.getProperty(runtime.toJS);
  if (hostObject == null || !hostObject.isA<JSObject>()) {
    throw StateError('$runtime global is unavailable');
  }

  final config = JSObject()
    ..setProperty('hostname'.toJS, host.toJS)
    ..setProperty('port'.toJS, port.toJS);

  if (runtime == 'Bun') {
    config.setProperty('fetch'.toJS, callback);
    final serve = (hostObject as JSObject).getProperty('serve'.toJS);
    if (serve == null || !serve.isA<JSFunction>()) {
      throw StateError('Bun.serve is unavailable');
    }
    final result = (serve as JSFunction).callAsFunction(hostObject, config);
    if (result == null || !result.isA<JSObject>()) {
      throw StateError('Bun.serve did not return a server');
    }
    return result as JSObject;
  }

  final serve = (hostObject as JSObject).getProperty('serve'.toJS);
  if (serve == null || !serve.isA<JSFunction>()) {
    throw StateError('Deno.serve is unavailable');
  }
  final result = (serve as JSFunction).callAsFunction(
    hostObject,
    config,
    callback,
  );
  if (result != null && result.isA<JSObject>()) return result as JSObject;
  throw StateError('Deno.serve did not return a server');
}
