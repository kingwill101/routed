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

/// Owns pending and active WebSocket state for one Bun server.
final Map<JSObject, BunWebSocketRegistry> _registries =
    <JSObject, BunWebSocketRegistry>{};

final class BunWebSocketRegistry {
  final Map<int, BunWebSocketBridge> _bridges = <int, BunWebSocketBridge>{};
  int _nextId = 0;

  FetchWebSocketUpgrade prepare(JSObject request, JSObject server) {
    final id = ++_nextId;
    final bridge = BunWebSocketBridge(id: id, registry: this);
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

  void open(JSObject socket, JSAny data) {
    _bridgeFor(data)?.open(socket);
  }

  void message(JSAny data, JSAny message) {
    _bridgeFor(data)?.message(message);
  }

  void close(JSAny data, {int? code, String? reason}) {
    final bridge = _remove(_bridgeId(data));
    bridge?.closeFromHost(code, reason);
  }

  void error(JSAny data, JSAny error) {
    final bridge = _remove(_bridgeId(data));
    bridge?.error(error);
  }

  void unregister() {
    _registries.removeWhere((server, registry) => identical(registry, this));
  }

  void closeAll() {
    for (final bridge in List<BunWebSocketBridge>.of(_bridges.values)) {
      unawaited(bridge.close(1001, 'Runtime shutdown'));
    }
  }

  Future<void> waitForAll() async {
    await Future.wait(
      List<BunWebSocketBridge>.of(
        _bridges.values,
      ).map((bridge) => bridge.closed),
    );
  }

  BunWebSocketBridge? _bridgeFor(JSAny data) => _bridges[_bridgeId(data)];

  BunWebSocketBridge? _remove(int id) => _bridges.remove(id);
}

final class BunWebSocketBridge implements RoutedWebSocket {
  BunWebSocketBridge({required this.id, required this.registry});

  final int id;
  final BunWebSocketRegistry registry;
  final StreamController<Object?> _messages = StreamController<Object?>();
  final Completer<void> _closedCompleter = Completer<void>();
  final List<JSAny> _pending = <JSAny>[];
  _BunWebSocket? _socket;
  bool _closed = false;
  bool _closeSent = false;
  int? _closeCode;

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

  void closeFromHost([int? code, String? reason]) {
    if (_closed) return;
    _closeCode = code;
    _closed = true;
    registry._remove(id);
    if (!_messages.isClosed) unawaited(_messages.close());
    _completeClosed();
  }

  void error(JSAny error) {
    if (_closed) return;
    _messages.addError(StateError('$error'));
    closeFromHost(1006, 'error');
  }

  @override
  Stream<Object?> get stream => _messages.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void add(Object? data) {
    if (_closed || _closeSent) throw StateError('WebSocket is closed.');
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
    _closeSent = true;
    final socket = _socket;
    if (socket != null) socket.close(code ?? 1000, reason ?? '');
    await _closedCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => closeFromHost(code ?? 1000, reason),
    );
  }

  Future<void> get closed => _closedCompleter.future;

  void _completeClosed() {
    if (!_closedCompleter.isCompleted) _closedCompleter.complete();
  }
}

void registerBunWebSocketRegistry(
  JSObject server,
  BunWebSocketRegistry registry,
) {
  _registries[server] = registry;
}

void closeBunWebSocketsForServer(JSObject server) {
  _registries[server]?.closeAll();
}

Future<void> waitForBunWebSocketsForServer(JSObject server) async {
  final registry = _registries[server];
  if (registry == null) return;
  await registry.waitForAll();
  registry.unregister();
}

Future<FetchWebSocketUpgrade> acceptBunWebSocket(
  JSObject request,
  JSObject server,
  BunWebSocketRegistry registry,
) async => registry.prepare(request, server);

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
  if (message.isA<JSArrayBuffer>()) {
    return (message as JSArrayBuffer).toDart.asUint8List();
  }
  return message;
}

JSAny _bunData(Object? data) {
  if (data is String) return data.toJS;
  if (data is List<int>) return Uint8List.fromList(data).toJS;
  return (data?.toString() ?? '').toJS;
}
