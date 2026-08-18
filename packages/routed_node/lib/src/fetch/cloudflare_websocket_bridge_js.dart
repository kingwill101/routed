// ignore_for_file: library_private_types_in_public_api,
// invalid_runtime_check_with_js_interop_types

@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:routed_core/routed_core.dart';

import 'fetch_exchange.dart';

extension type _NativeWebSocket._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction? callback);
  external void send(JSAny data);
  external void close([int code, String reason]);
}

@JS('WebSocketPair')
extension type _CloudflareWebSocketPair._(JSObject _) implements JSObject {
  external factory _CloudflareWebSocketPair();

  @JS('0')
  external JSObject get client;

  @JS('1')
  external JSObject get server;
}

final class WebFetchWebSocket implements RoutedWebSocket {
  WebFetchWebSocket(this.socket);

  final _NativeWebSocket socket;
  final StreamController<JSAny?> _messages = StreamController<JSAny?>();
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    socket.addEventListener(
      'message',
      ((JSAny event) {
        final object = event as JSObject;
        _messages.add(object.getProperty('data'.toJS));
      }).toJS,
    );
    socket.addEventListener(
      'close',
      (() {
        unawaited(_messages.close());
      }).toJS,
    );
  }

  @override
  Stream<JSAny?> get stream {
    attach();
    return _messages.stream;
  }

  @override
  int? get closeCode => null;

  @override
  void add(Object? data) {
    if (data is String) {
      socket.send(data.toJS);
    } else if (data is JSAny) {
      socket.send(data);
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

Future<FetchWebSocketUpgrade> cloudflareWebSocketPair() async {
  final pair = _CloudflareWebSocketPair();
  final server = pair.server;
  server.callMethodVarArgs<JSAny?>('accept'.toJS);
  return FetchWebSocketUpgrade(
    socket: WebFetchWebSocket(_NativeWebSocket._(server)),
    response: pair.client,
  );
}
