// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';
import 'package:routed/routed.dart';

class WebSocketContext {
  final WebSocket webSocket;
  final EngineContext initialContext;
  WebSocketContext(this.webSocket, this.initialContext);
  void send(dynamic data) {
    webSocket.add(data);
  }
  Future<void> close([int? code, String? reason]) {
    return webSocket.close(code, reason);
  }
}

abstract class WebSocketHandler {
  FutureOr<void> onOpen(WebSocketContext context);
  FutureOr<void> onMessage(WebSocketContext context, dynamic message);
  FutureOr<void> onClose(WebSocketContext context);
  FutureOr<void> onError(WebSocketContext context, dynamic error);
}
