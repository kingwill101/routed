// ignore_for_file: library_private_types_in_public_api

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';

import '../fetch/fetch_exchange.dart';

extension type _DenoWebSocket._(JSObject _) implements JSObject {
  external void send(JSAny data);
  external void close([int code, String reason]);
}

/// Defines the public contract for this host integration.
final class DenoWebSocketBridge implements RoutedWebSocket {
  /// Performs the DenoWebSocketBridge operation.
  DenoWebSocketBridge(this.socket);

  /// The socket value.
  final _DenoWebSocket socket;
  final StreamController<Object?> _messages = StreamController<Object?>();

  /// Performs the attach operation.
  void attach() {
    socket.setProperty(
      'onmessage'.toJS,
      ((JSAny event) {
        final data = (event as JSObject).getProperty('data'.toJS);
        if (data != null) _messages.add(_denoMessage(data));
      }).toJS,
    );
    socket.setProperty(
      'onclose'.toJS,
      (() {
        unawaited(_messages.close());
      }).toJS,
    );
    socket.setProperty(
      'onerror'.toJS,
      ((JSAny error) {
        _messages.addError(StateError('$error'));
        unawaited(_messages.close());
      }).toJS,
    );
  }

  @override
  Stream<Object?> get stream {
    attach();
    return _messages.stream;
  }

  @override
  int? get closeCode => null;

  @override
  void add(Object? data) {
    if (data is String) {
      socket.send(data.toJS);
    } else if (data is List<int>) {
      socket.send(Uint8List.fromList(data).toJS);
    } else {
      socket.send((data?.toString() ?? '').toJS);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    socket.close(code ?? 1000, reason ?? '');
    await _messages.close();
  }
}

/// Performs the prepareDenoWebSocket operation.
FetchWebSocketUpgrade prepareDenoWebSocket(JSObject request) {
  final deno = globalContext.getProperty('Deno'.toJS);
  if (deno == null || !deno.isA<JSObject>()) {
    throw StateError('Deno global is unavailable');
  }
  final upgrade = (deno as JSObject).callMethodVarArgs<JSAny?>(
    'upgradeWebSocket'.toJS,
    [request],
  );
  if (upgrade == null || !upgrade.isA<JSObject>()) {
    throw StateError('Deno.upgradeWebSocket did not return an upgrade');
  }
  final result = upgrade as JSObject;
  final socket = result.getProperty('socket'.toJS);
  final response = result.getProperty('response'.toJS);
  if (socket == null || !socket.isA<JSObject>() || response == null) {
    throw StateError('Deno WebSocket upgrade is incomplete');
  }
  final bridge = DenoWebSocketBridge(_DenoWebSocket._(socket as JSObject));
  bridge.attach();
  return FetchWebSocketUpgrade(socket: bridge, response: response);
}

/// Performs the denoUpgradeResponse operation.
Object? denoUpgradeResponse(FetchWebSocketUpgrade upgrade) => upgrade.response;

Object? _denoMessage(JSAny data) {
  if (data.isA<JSString>()) return (data as JSString).toDart;
  if (data.isA<JSUint8Array>()) {
    return Uint8List.fromList((data as JSUint8Array).toDart);
  }
  return data;
}
