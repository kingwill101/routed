import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';

import 'node_portable.dart';
import 'node_request_adapter.dart';
import 'node_views.dart';
import 'node_websocket.dart';
import 'node_websocket_dispatch.dart';
import 'runtime/runtime.dart';

@JS('process.getBuiltinModule')
external JSAny? _getBuiltinModule(JSString name);

@JS('require')
external JSFunction? get _nodeRequire;

/// Loads Node's built-in `http` module.
JSObject? _loadNodeHttpModule() {
  try {
    final mod = _getBuiltinModule('node:http'.toJS);
    if (mod != null && mod.isA<JSObject>()) {
      return mod as JSObject;
    }
  } catch (_) {}

  final req = _nodeRequire;
  if (req != null) {
    try {
      final mod = req.callAsFunction(null, 'node:http'.toJS);
      if (mod != null && mod.isA<JSObject>()) return mod as JSObject;
    } catch (_) {}
  }
  return null;
}

extension type _NodeIncomingMessage._(JSObject _) implements JSObject {
  external String get method;
  external String get url;
  external JSObject get headers;
  external JSObject? get socket;
  external void on(String event, JSFunction listener);
}

extension type _NodeServerResponse._(JSObject _) implements JSObject {
  external void writeHead(int statusCode, JSObject headers);
  external bool write(JSAny chunk);
  external void end([JSAny? data]);
  external bool get writableEnded;
}

extension type _NodeSocket._(JSObject _) implements JSObject {
  external String? get remoteAddress;
  external void on(String event, JSFunction listener);
  external void once(String event, JSFunction listener);
  external void removeListener(String event, JSFunction listener);
  external void write(JSAny data, [JSFunction? callback]);
  external void end([JSAny? data]);
  external void destroy();
}

final class _JsWebSocketSocket implements NodeWebSocketSocketView {
  _JsWebSocketSocket(this.socket, {List<int> head = const []}) : _head = head;

  final _NodeSocket socket;
  final List<int> _head;
  final StreamController<List<int>> _incoming = StreamController<List<int>>();
  bool _attached = false;

  void _attach() {
    if (_attached) return;
    _attached = true;
    if (_head.isNotEmpty) _incoming.add(_head);
    socket.on(
      'data',
      ((JSAny chunk) {
        final bytes = _chunkToBytes(chunk);
        if (bytes.isNotEmpty) _incoming.add(bytes);
      }).toJS,
    );
    socket.on(
      'end',
      (() {
        unawaited(_incoming.close());
      }).toJS,
    );
    socket.on(
      'close',
      (() {
        unawaited(_incoming.close());
      }).toJS,
    );
    socket.on(
      'error',
      ((JSAny error) {
        if (!_incoming.isClosed) _incoming.addError(StateError('$error'));
      }).toJS,
    );
  }

  @override
  Stream<List<int>> get incoming {
    _attach();
    return _incoming.stream;
  }

  @override
  Future<void> write(List<int> bytes) {
    _attach();
    final done = Completer<void>();
    socket.write(Uint8List.fromList(bytes).toJS, (() => done.complete()).toJS);
    return done.future;
  }

  @override
  Future<void> end([List<int>? bytes]) async {
    _attach();
    socket.end(bytes == null ? null : Uint8List.fromList(bytes).toJS);
  }

  @override
  void destroy() => socket.destroy();
}

/// Live Node view of IncomingMessage.
final class _JsIncoming implements NodeIncomingView {
  _JsIncoming(this._msg);

  final _NodeIncomingMessage _msg;
  final StreamController<List<int>> _body =
      StreamController<List<int>>.broadcast();
  bool _listening = false;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _msg.on(
      'data',
      ((JSAny chunk) {
        final bytes = _chunkToBytes(chunk);
        if (bytes.isNotEmpty) _body.add(bytes);
      }).toJS,
    );
    _msg.on(
      'end',
      (() {
        if (!_body.isClosed) _body.close();
      }).toJS,
    );
    _msg.on(
      'error',
      ((JSAny err) {
        if (!_body.isClosed) {
          _body.addError(StateError('Node request stream error: $err'));
          _body.close();
        }
      }).toJS,
    );
  }

  @override
  String get method => _msg.method;

  @override
  String get url => _msg.url;

  @override
  Map<String, Object?> get rawHeaders {
    final out = <String, Object?>{};
    final headers = _msg.headers;
    final keys = _objectKeys(headers);
    for (final key in keys) {
      final value = headers.getProperty(key.toJS);
      out[key] = _jsHeaderValue(value);
    }
    return out;
  }

  @override
  String? get remoteAddress {
    final socket = _msg.socket;
    if (socket == null) return null;
    return _NodeSocket._(socket).remoteAddress;
  }

  @override
  Stream<List<int>> get body {
    _ensureListening();
    return _body.stream;
  }
}

final class _JsOutgoing implements NodeServerResponseView {
  _JsOutgoing(this._res);

  final _NodeServerResponse _res;

  @override
  void writeHead(int statusCode, Map<String, Object> headers) {
    final jsHeaders = JSObject();
    headers.forEach((name, value) {
      if (value is List) {
        final arr = JSArray();
        for (var i = 0; i < value.length; i++) {
          arr.setProperty(i.toJS, value[i].toString().toJS);
        }
        jsHeaders.setProperty(name.toJS, arr);
      } else {
        jsHeaders.setProperty(name.toJS, value.toString().toJS);
      }
    });
    _res.writeHead(statusCode, jsHeaders);
  }

  @override
  void write(List<int> bytes) {
    _res.write(Uint8List.fromList(bytes).toJS);
  }

  @override
  void end([List<int>? bytes]) {
    if (bytes != null && bytes.isNotEmpty) {
      _res.end(Uint8List.fromList(bytes).toJS);
    } else {
      _res.end();
    }
  }

  @override
  bool get finished => _res.writableEnded;
}

String? _header(Map<String, Object?> headers, String name) {
  final value = headers[name];
  if (value is List && value.isNotEmpty) return value.first.toString();
  return value?.toString();
}

List<int> _chunkToBytes(JSAny chunk) {
  // Node may pass Buffer / Uint8Array / string.
  if (chunk.isA<JSString>()) {
    return (chunk as JSString).toDart.codeUnits;
  }
  // Prefer Uint8Array view when available.
  if (chunk.isA<JSUint8Array>()) {
    return (chunk as JSUint8Array).toDart;
  }
  // Fallback: empty (unsupported chunk type).
  return const [];
}

Object? _jsHeaderValue(JSAny? value) {
  if (value == null) return null;
  if (value.isA<JSString>()) return (value as JSString).toDart;
  if (value.isA<JSArray>()) {
    final arr = value as JSArray;
    final len = arr.length;
    final list = <String>[];
    for (var i = 0; i < len; i++) {
      final item = arr.getProperty(i.toJS);
      if (item != null) list.add(item.toString());
    }
    return list;
  }
  return value.toString();
}

List<String> _objectKeys(JSObject obj) {
  final keysFn = globalContext.getProperty('Object'.toJS) as JSObject?;
  if (keysFn == null) return const [];
  final keysMethod = keysFn.getProperty('keys'.toJS) as JSFunction?;
  if (keysMethod == null) return const [];
  final result = keysMethod.callAsFunction(keysFn, obj);
  if (result == null || !result.isA<JSArray>()) return const [];
  final arr = result as JSArray;
  final out = <String>[];
  for (var i = 0; i < arr.length; i++) {
    final k = arr.getProperty(i.toJS);
    if (k != null) out.add(k.toString());
  }
  return out;
}

/// Keeps standalone dart2js Node processes attached to the event loop.
void keepNodeEventLoopAlive() {
  final setInterval = globalContext.getProperty('setInterval'.toJS);
  if (setInterval != null && setInterval.isA<JSFunction>()) {
    (setInterval as JSFunction).callAsFunction(null, (() {}).toJS, 60_000.toJS);
  }
}

/// Bind [engine] using Node `http.createServer`.
Future<ServerHandle> bindNodeHttp(
  Engine engine,
  ServerOptions options, {
  bool echo = false,
}) async {
  if (engine.isClosed) {
    throw StateError('Cannot serve on a closed engine');
  }
  keepNodeEventLoopAlive();
  await engine.initialize();

  final mod = _loadNodeHttpModule();
  if (mod == null) {
    throw StateError(
      'Unable to load node:http. Need Node ≥ 22 (process.getBuiltinModule) '
      'or a bootstrap that exposes globalThis.require.',
    );
  }
  final createServer = mod.getProperty('createServer'.toJS);
  if (createServer == null || !createServer.isA<JSFunction>()) {
    throw StateError('node:http.createServer is missing');
  }

  final completer = Completer<void>();

  final created = (createServer as JSFunction).callAsFunction(
    mod,
    ((JSAny req, JSAny res) {
      final incoming = _JsIncoming(_NodeIncomingMessage._(req as JSObject));
      final outgoing = _JsOutgoing(_NodeServerResponse._(res as JSObject));
      final base = Uri(
        scheme: 'http',
        host: options.host,
        port: options.port == 0 ? null : options.port,
      );
      final hostContext = RoutedNodeContext(
        info: const RoutedNodeRuntimeInfo(
          runtime: RoutedNodeRuntime.node,
          capabilities: nodeCapabilities,
        ),
        extension: NodeRuntimeExtension(
          request: req,
          response: res,
          server: null,
        ),
      );
      // Value-style edge: Node → PortableRequest → engine → PortableResponse → Node
      unawaited(
        dispatchNodeExchange(
          engine,
          incoming,
          outgoing,
          baseUri: base,
          hostContext: hostContext,
        ).catchError((Object e, StackTrace s) async {
          try {
            if (!outgoing.finished) {
              outgoing.writeHead(500, {'Content-Type': 'text/plain'});
              outgoing.end('Internal Server Error'.codeUnits);
            }
          } catch (_) {}
        }),
      );
    }).toJS,
  );
  if (created == null || !created.isA<JSObject>()) {
    throw StateError('http.createServer did not return a server');
  }
  final serverObj = created as JSObject;

  final onUpgrade = serverObj.getProperty('on'.toJS);
  if (onUpgrade != null && onUpgrade.isA<JSFunction>()) {
    (onUpgrade as JSFunction).callAsFunction(
      serverObj,
      'upgrade'.toJS,
      ((JSAny req, JSAny socket, JSAny head) {
        final incoming = _JsIncoming(_NodeIncomingMessage._(req as JSObject));
        final nodeSocket = _JsWebSocketSocket(
          _NodeSocket._(socket as JSObject),
          head: _chunkToBytes(head),
        );
        final rawHeaders = incoming.rawHeaders;
        final upgrade =
            _header(rawHeaders, 'upgrade')?.toLowerCase() == 'websocket';
        final connection =
            _header(rawHeaders, 'connection')
                ?.toLowerCase()
                .split(',')
                .map((v) => v.trim())
                .contains('upgrade') ??
            false;
        final key = _header(rawHeaders, 'sec-websocket-key');
        final version = _header(rawHeaders, 'sec-websocket-version');
        if (!upgrade || !connection || key == null || version != '13') {
          nodeSocket.end(
            Uint8List.fromList(
              utf8.encode(
                'HTTP/1.1 400 Bad Request\\r\\nConnection: close\\r\\n\\r\\n',
              ),
            ),
          );
          return;
        }
        final base = Uri(
          scheme: 'http',
          host: options.host,
          port: options.port == 0 ? null : options.port,
        );
        final protocols = _header(rawHeaders, 'sec-websocket-protocol')
            ?.split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        final protocol = protocols?.isNotEmpty == true
            ? protocols!.first
            : null;
        final response = NodeWebSocketUpgradeResponse(
          socket: nodeSocket,
          key: key,
          protocol: protocol,
        );
        final hostContext = RoutedNodeContext(
          info: const RoutedNodeRuntimeInfo(
            runtime: RoutedNodeRuntime.node,
            capabilities: nodeCapabilities,
          ),
          extension: NodeRuntimeExtension(
            request: req,
            response: socket,
            server: serverObj,
          ),
        );
        final adapter = NodeRequestAdapter(
          incoming,
          baseUri: base,
          hostContext: hostContext,
          isWebSocketUpgrade: true,
          acceptWebSocket: () async {
            await nodeSocket.write(response.handshake);
            return NodeRoutedWebSocket(socket: nodeSocket);
          },
          upgradeResponse: () => response,
        );
        unawaited(dispatchNodeWebSocket(engine, adapter, nodeSocket));
      }).toJS,
    );
  }

  final listen = serverObj.getProperty('listen'.toJS);
  if (listen == null || !listen.isA<JSFunction>()) {
    throw StateError('server.listen is missing');
  }
  (listen as JSFunction).callAsFunction(
    serverObj,
    options.port.toJS,
    options.host.toJS,
    (() {
      if (!completer.isCompleted) completer.complete();
    }).toJS,
  );

  await completer.future;

  // Resolve actual bound port (important when port == 0).
  var boundPort = options.port;
  final addressFn = serverObj.getProperty('address'.toJS);
  if (addressFn != null && addressFn.isA<JSFunction>()) {
    final addr = (addressFn as JSFunction).callAsFunction(serverObj);
    if (addr != null && addr.isA<JSObject>()) {
      final portVal = (addr as JSObject).getProperty('port'.toJS);
      if (portVal != null && portVal.isA<JSNumber>()) {
        boundPort = (portVal as JSNumber).toDartInt;
      }
    }
  }

  if (echo) {
    // ignore: avoid_print
    print('Engine listening on http://${options.host}:$boundPort');
  }

  return _NodeServerHandle(serverObj, options.host, boundPort);
}

final class _NodeServerHandle implements ServerHandle {
  _NodeServerHandle(this._server, this._host, this._port);

  final JSObject _server;
  final String _host;
  final int _port;

  @override
  String get host => _host;

  @override
  int get port {
    final addressFn = _server.getProperty('address'.toJS);
    if (addressFn != null && addressFn.isA<JSFunction>()) {
      final addr = (addressFn as JSFunction).callAsFunction(_server);
      if (addr != null && addr.isA<JSObject>()) {
        final portVal = (addr as JSObject).getProperty('port'.toJS);
        if (portVal != null && portVal.isA<JSNumber>()) {
          return (portVal as JSNumber).toDartInt;
        }
      }
    }
    return _port;
  }

  @override
  Future<void> close({bool force = false}) {
    final done = Completer<void>();
    final closeFn = _server.getProperty('close'.toJS);
    if (closeFn != null && closeFn.isA<JSFunction>()) {
      (closeFn as JSFunction).callAsFunction(
        _server,
        (() {
          if (!done.isCompleted) done.complete();
        }).toJS,
      );
    } else if (!done.isCompleted) {
      done.complete();
    }
    return done.future;
  }
}
