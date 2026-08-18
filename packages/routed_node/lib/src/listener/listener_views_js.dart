@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';
import 'package:web/web.dart' as web;

import '../fetch/fetch_entry_js.dart';
import '../fetch/fetch_exchange.dart';
import '../fetch/web_fetch_adapter_js.dart';
import '../runtime/runtime.dart';
import 'bun_websocket_bridge_js.dart';
import 'deno_websocket_bridge_js.dart';

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

  final bunSockets = BunWebSocketRegistry();
  late JSObject bunServer;
  final callback = ((JSAny request) {
    final nativeRequest = web.Request(request);
    if (_isWebSocketUpgrade(nativeRequest)) {
      if (runtime == 'Bun') {
        return _handleBunUpgrade(
          engine,
          info,
          nativeRequest,
          request as JSObject,
          bunServer,
          bunSockets,
        ).toJS;
      }
      return _handleDenoUpgrade(
        engine,
        info,
        nativeRequest,
        request as JSObject,
      ).toJS;
    }
    return handleNativeFetch(engine, info, nativeRequest).toJS;
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
    config
      ..setProperty('fetch'.toJS, callback)
      ..setProperty('websocket'.toJS, _bunWebSocketHandler(bunSockets));
    final serve = (hostObject as JSObject).getProperty('serve'.toJS);
    if (serve == null || !serve.isA<JSFunction>()) {
      throw StateError('Bun.serve is unavailable');
    }
    final result = (serve as JSFunction).callAsFunction(hostObject, config);
    if (result == null || !result.isA<JSObject>()) {
      throw StateError('Bun.serve did not return a server');
    }
    bunServer = result as JSObject;
    registerBunWebSocketRegistry(bunServer, bunSockets);
    return bunServer;
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

Future<JSAny?> _handleDenoUpgrade(
  Engine engine,
  RoutedNodeRuntimeInfo info,
  web.Request request,
  JSObject rawRequest,
) async {
  final view = WebFetchRequest(
    request,
    hostContext: RoutedNodeContext(
      info: info,
      extension: FetchRuntimeExtension(runtime: info.runtime, request: request),
    ),
  );
  final response = WebStreamingResponseAdapter();
  final adapter = _DenoRequestAdapter(
    view,
    acceptFactory: () async => prepareDenoWebSocket(rawRequest),
  );
  await engine.handleConnection(HttpConnection(adapter, response));
  final upgrade = adapter.upgrade;
  if (upgrade != null) return upgrade.response as JSAny;
  return webResponseFromStreamingAdapter(response);
}

bool _isWebSocketUpgrade(web.Request request) {
  final upgrade = request.headers.get('upgrade')?.toLowerCase();
  final connection = request.headers.get('connection');
  return request.method.toUpperCase() == 'GET' &&
      upgrade == 'websocket' &&
      (connection
              ?.split(',')
              .map((value) => value.trim().toLowerCase())
              .contains('upgrade') ??
          false);
}

JSObject _bunWebSocketHandler(BunWebSocketRegistry registry) {
  final handler = JSObject();
  handler.setProperty(
    'open'.toJS,
    ((JSObject socket) {
      final data = socket.getProperty('data'.toJS);
      if (data != null) registry.open(socket, data);
    }).toJS,
  );
  handler.setProperty(
    'message'.toJS,
    ((JSObject socket, JSAny message) {
      final data = socket.getProperty('data'.toJS);
      if (data != null) registry.message(data, message);
    }).toJS,
  );
  handler.setProperty(
    'close'.toJS,
    ((JSObject socket) {
      final data = socket.getProperty('data'.toJS);
      if (data != null) registry.close(data);
    }).toJS,
  );
  handler.setProperty(
    'error'.toJS,
    ((JSObject socket, JSAny error) {
      final data = socket.getProperty('data'.toJS);
      if (data != null) registry.error(data, error);
    }).toJS,
  );
  return handler;
}

Future<JSAny?> _handleBunUpgrade(
  Engine engine,
  RoutedNodeRuntimeInfo info,
  web.Request request,
  JSObject rawRequest,
  JSObject server,
  BunWebSocketRegistry registry,
) async {
  final hostContext = RoutedNodeContext(
    info: info,
    extension: FetchRuntimeExtension(runtime: info.runtime, request: request),
  );
  final view = WebFetchRequest(
    request,
    hostContext: hostContext,
    acceptWebSocket: () => acceptBunWebSocket(rawRequest, server, registry),
  );
  final response = WebStreamingResponseAdapter();
  final adapter = _BunRequestAdapter(view);
  await engine.handleConnection(HttpConnection(adapter, response));
  if (adapter.upgrade != null) return null;
  return webResponseFromStreamingAdapter(response);
}

final class _DenoRequestAdapter
    implements RequestAdapter, WebSocketUpgradeRequest, HostContextCarrier {
  _DenoRequestAdapter(this.view, {required this.acceptFactory});

  final WebFetchRequest view;
  final Future<FetchWebSocketUpgrade> Function() acceptFactory;
  FetchWebSocketUpgrade? upgrade;

  @override
  Object? get hostContext => view.hostContext;
  @override
  String get method => view.method;
  @override
  Uri get uri => Uri.parse(view.url);
  @override
  Map<String, List<String>> get headers =>
      view.rawHeaders.map((key, value) => MapEntry(key, [value.toString()]));
  @override
  Stream<List<int>> get body => view.body;
  @override
  String? get remoteAddress => view.remoteAddress;
  @override
  bool get isWebSocketUpgrade => true;
  @override
  Future<RoutedWebSocket> accept() async {
    upgrade ??= await acceptFactory();
    return upgrade!.socket;
  }

  @override
  Object? get nativeUpgradeResponse => upgrade?.response;
}

final class _BunRequestAdapter
    implements RequestAdapter, WebSocketUpgradeRequest, HostContextCarrier {
  _BunRequestAdapter(this.view);

  final WebFetchRequest view;
  FetchWebSocketUpgrade? upgrade;

  @override
  Object? get hostContext => view.hostContext;

  @override
  String get method => view.method;

  @override
  Uri get uri => Uri.parse(view.url);

  @override
  Map<String, List<String>> get headers =>
      view.rawHeaders.map((key, value) => MapEntry(key, [value.toString()]));

  @override
  Stream<List<int>> get body => view.body;

  @override
  String? get remoteAddress => view.remoteAddress;

  @override
  bool get isWebSocketUpgrade => true;

  @override
  Future<RoutedWebSocket> accept() async {
    final accept = view.acceptWebSocket;
    if (accept == null) throw UnsupportedError('Bun WebSocket is unavailable.');
    upgrade ??= await accept();
    return upgrade!.socket;
  }

  @override
  Object? get nativeUpgradeResponse => null;
}
