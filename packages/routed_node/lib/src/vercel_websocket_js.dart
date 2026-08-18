import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';

import 'node_request_adapter.dart';
import 'node_views.dart';
import 'runtime/runtime.dart';

/// Installs the Vercel Functions WebSocket callback used by the generated
/// CommonJS entrypoint.
void defineVercelWebSocketHandler(Future<Engine> Function() getEngine) {
  final handler = ((JSAny request, JSAny webSocket) {
    return _dispatchVercelWebSocket(
      getEngine,
      request as JSObject,
      webSocket as JSObject,
    ).toJS;
  }).toJS;
  globalContext.setProperty('__routed_vercel_node_websocket__'.toJS, handler);
}

Future<void> _dispatchVercelWebSocket(
  Future<Engine> Function() getEngine,
  JSObject request,
  JSObject webSocket,
) async {
  final incoming = _VercelIncomingMessage(request);
  final hostContext = RoutedNodeContext(
    info: const RoutedNodeRuntimeInfo(
      runtime: RoutedNodeRuntime.vercel,
      capabilities: vercelNodeCapabilities,
    ),
    extension: VercelNodeRuntimeExtension(
      request: request,
      response: webSocket,
    ),
  );
  final adapter = NodeRequestAdapter(
    incoming,
    baseUri: Uri(scheme: 'https', host: 'localhost'),
    hostContext: hostContext,
    isWebSocketUpgrade: true,
    acceptWebSocket: () async => _VercelRoutedWebSocket(webSocket),
  );
  await (await getEngine()).handleConnection(
    HttpConnection(adapter, _VercelResponseAdapter()),
  );
}

final class _VercelIncomingMessage implements NodeIncomingView {
  _VercelIncomingMessage(this.request);

  final JSObject request;

  @override
  String get method => _stringProperty(request, 'method') ?? 'GET';

  @override
  String get url => _stringProperty(request, 'url') ?? '/';

  @override
  Map<String, Object?> get rawHeaders => _headers(request);

  @override
  String? get remoteAddress => null;

  @override
  Stream<List<int>> get body => const Stream<List<int>>.empty();
}

final class _VercelResponseAdapter
    implements ResponseAdapter, WebSocketResponseAdapter {
  int _statusCode = 200;

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) => _statusCode = value;

  @override
  void setHeader(String name, String value) {}

  @override
  void addHeader(String name, String value) {}

  @override
  void write(List<int> bytes) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  void upgrade(Object nativeWebSocket) {}
}

final class _VercelRoutedWebSocket implements RoutedWebSocket {
  _VercelRoutedWebSocket(this._webSocket) {
    _on(
      'message',
      ((JSAny data, JSAny isBinary) {
        _messages.add(
          isBinary.isA<JSBoolean>() && (isBinary as JSBoolean).toDart
              ? _bytes(data)
              : _message(data),
        );
      }).toJS,
    );
    _on(
      'error',
      ((JSAny error) {
        _messages.addError(StateError(error.toString()));
      }).toJS,
    );
    _on(
      'close',
      ((JSAny code, JSAny reason) {
        final value = code.isA<JSNumber>()
            ? (code as JSNumber).toDartInt
            : null;
        _closeCode = value;
        if (!_messages.isClosed) unawaited(_messages.close());
      }).toJS,
    );
  }

  final JSObject _webSocket;
  final StreamController<Object?> _messages = StreamController<Object?>();
  int? _closeCode;
  bool _closed = false;

  @override
  Stream<Object?> get stream => _messages.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void add(Object? data) {
    if (_closed) throw StateError('WebSocket is closed.');
    final send = _webSocket.getProperty('send'.toJS);
    if (send == null || !send.isA<JSFunction>()) {
      throw StateError('Vercel WebSocket does not expose send().');
    }
    final value = data is List<int>
        ? Uint8List.fromList(data).toJS
        : (data?.toString() ?? '').toJS;
    (send as JSFunction).callAsFunction(_webSocket, value);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    final close = _webSocket.getProperty('close'.toJS);
    if (close == null || !close.isA<JSFunction>()) return;
    if (code == null) {
      (close as JSFunction).callAsFunction(_webSocket);
    } else {
      (close as JSFunction).callAsFunction(
        _webSocket,
        code.toJS,
        (reason ?? '').toJS,
      );
    }
  }

  void _on(String event, JSFunction callback) {
    final on = _webSocket.getProperty('on'.toJS);
    if (on == null || !on.isA<JSFunction>()) {
      throw StateError('Vercel WebSocket does not expose on().');
    }
    (on as JSFunction).callAsFunction(_webSocket, event.toJS, callback);
  }

  Object _message(JSAny data) {
    if (data.isA<JSString>()) return (data as JSString).toDart;
    return String.fromCharCodes(_bytes(data));
  }

  Uint8List _bytes(JSAny data) {
    if (data.isA<JSUint8Array>()) return (data as JSUint8Array).toDart;
    return Uint8List.fromList(const []);
  }
}

String? _stringProperty(JSObject object, String name) {
  final value = object.getProperty(name.toJS);
  return value != null && value.isA<JSString>()
      ? (value as JSString).toDart
      : null;
}

Map<String, Object?> _headers(JSObject request) {
  final headers = request.getProperty('headers'.toJS);
  if (headers == null || !headers.isA<JSObject>()) return const {};
  final headersObject = headers as JSObject;
  final out = <String, Object?>{};
  final entries = headersObject.getProperty('entries'.toJS);
  if (entries == null || !entries.isA<JSFunction>()) {
    return _plainObjectHeaders(headersObject);
  }
  final iterator = (entries as JSFunction).callAsFunction(headersObject);
  if (iterator == null || !iterator.isA<JSObject>()) return out;
  final iteratorObject = iterator as JSObject;
  final next = iteratorObject.getProperty('next'.toJS);
  if (next == null || !next.isA<JSFunction>()) return out;
  while (true) {
    final item = (next as JSFunction).callAsFunction(iteratorObject);
    if (item == null || !item.isA<JSObject>()) break;
    final itemObject = item as JSObject;
    final done = itemObject.getProperty('done'.toJS);
    if (done != null && done.isA<JSBoolean>() && (done as JSBoolean).toDart) {
      break;
    }
    final value = itemObject.getProperty('value'.toJS);
    if (value == null || !value.isA<JSArray>()) break;
    final valueArray = value as JSArray;
    if (valueArray.length < 2) break;
    final name = valueArray.getProperty(0.toJS);
    final headerValue = valueArray.getProperty(1.toJS);
    if (name != null &&
        headerValue != null &&
        name.isA<JSString>() &&
        headerValue.isA<JSString>()) {
      out[(name as JSString).toDart] = (headerValue as JSString).toDart;
    }
  }
  return out;
}

Map<String, Object?> _plainObjectHeaders(JSObject headers) {
  final out = <String, Object?>{};
  final object = globalContext.getProperty('Object'.toJS);
  if (object == null || !object.isA<JSObject>()) return out;
  final keys = (object as JSObject).getProperty('keys'.toJS);
  if (keys == null || !keys.isA<JSFunction>()) return out;
  final values = (keys as JSFunction).callAsFunction(object, headers);
  if (values == null || !values.isA<JSArray>()) return out;
  final array = values as JSArray;
  for (var i = 0; i < array.length; i++) {
    final key = array.getProperty(i.toJS);
    if (key == null || !key.isA<JSString>()) continue;
    final value = headers.getProperty(key);
    if (value == null) continue;
    out[(key as JSString).toDart] = value.isA<JSString>()
        ? (value as JSString).toDart
        : value.toString();
  }
  return out;
}
