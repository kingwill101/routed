// ignore_for_file: library_private_types_in_public_api

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';

import '../fetch/fetch_exchange.dart';

extension type _BunWebSocket._(JSObject _) implements JSObject {
  external void send(JSAny data);
  external void close([int code, String reason]);
}

final class BunWebSocketBridge implements RoutedWebSocket {
  BunWebSocketBridge();

  final StreamController<Object?> _messages = StreamController<Object?>();
  final List<JSAny> _pending = <JSAny>[];
  _BunWebSocket? _socket;
  bool _closed = false;

  void open(JSObject socket) {
    if (_closed) return;
    _socket = _BunWebSocket._(socket);
    for (final message in _pending) {
      _socket!.send(message);
    }
    _pending.clear();
  }

  void message(JSAny message) {
    if (_closed) return;
    _messages.add(_bunMessage(message));
  }

  void closeFromHost() {
    if (_closed) return;
    _closed = true;
    unawaited(_messages.close());
  }

  void error(JSAny error) {
    if (_closed) return;
    _messages.addError(StateError('$error'));
    closeFromHost();
  }

  @override
  Stream<Object?> get stream => _messages.stream;

  @override
  int? get closeCode => null;

  @override
  void add(Object? data) {
    if (_closed) throw StateError('WebSocket is closed.');
    final message = _bunData(data);
    final socket = _socket;
    if (socket == null) {
      _pending.add(message);
    } else {
      socket.send(message);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    final socket = _socket;
    if (socket != null) socket.close(code ?? 1000, reason ?? '');
    await _messages.close();
  }
}

final Map<int, BunWebSocketBridge> _bridges = <int, BunWebSocketBridge>{};
int _nextBridgeId = 0;

FetchWebSocketUpgrade prepareBunWebSocket(JSObject request, JSObject server) {
  final id = ++_nextBridgeId;
  final bridge = BunWebSocketBridge();
  _bridges[id] = bridge;
  final options = JSObject()..setProperty('data'.toJS, id.toJS);
  final upgraded = server.callMethodVarArgs<JSAny?>('upgrade'.toJS, [
    request,
    options,
  ]);
  if (upgraded == null ||
      (upgraded.isA<JSBoolean>() && !(upgraded as JSBoolean).toDart)) {
    _bridges.remove(id);
    throw StateError('Bun server rejected the WebSocket upgrade.');
  }
  return FetchWebSocketUpgrade(socket: bridge, response: id);
}

Future<FetchWebSocketUpgrade> acceptBunWebSocket(
  JSObject request,
  JSObject server,
) async => prepareBunWebSocket(request, server);

void bunWebSocketOpen(JSObject socket, JSAny data) {
  final bridge = _bridgeFor(data);
  bridge?.open(socket);
}

void bunWebSocketMessage(JSAny data, JSAny message) {
  final bridge = _bridgeFor(data);
  bridge?.message(message);
}

void bunWebSocketClose(JSAny data) {
  final id = _bridgeId(data);
  final bridge = _bridges.remove(id);
  bridge?.closeFromHost();
}

void bunWebSocketError(JSAny data, JSAny error) {
  final id = _bridgeId(data);
  final bridge = _bridges.remove(id);
  bridge?.error(error);
}

BunWebSocketBridge? _bridgeFor(JSAny data) => _bridges[_bridgeId(data)];

int _bridgeId(JSAny data) {
  if (data.isA<JSNumber>()) return (data as JSNumber).toDartInt;
  if (data.isA<JSObject>()) {
    final id = (data as JSObject).getProperty('data'.toJS);
    if (id != null && id.isA<JSNumber>()) return (id as JSNumber).toDartInt;
  }
  return -1;
}

Object? _bunMessage(JSAny message) {
  if (message.isA<JSString>()) return (message as JSString).toDart;
  if (message.isA<JSUint8Array>()) {
    return Uint8List.fromList((message as JSUint8Array).toDart);
  }
  return message;
}

JSAny _bunData(Object? data) {
  if (data is String) return data.toJS;
  if (data is List<int>) return Uint8List.fromList(data).toJS;
  return (data?.toString() ?? '').toJS;
}
