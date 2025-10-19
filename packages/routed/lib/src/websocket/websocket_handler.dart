import 'dart:io';
import 'dart:async';

import 'package:routed/src/context/context.dart';

/// Represents the context for a WebSocket connection.
class WebSocketContext {
  /// The underlying WebSocket connection.
  final WebSocket webSocket;

  /// The initial HTTP context from the upgrade request.
  final EngineContext initialContext;

  WebSocketContext(this.webSocket, this.initialContext);

  /// Sends data over the WebSocket connection.
  void send(dynamic data) {
    webSocket.add(data);
  }

  /// Closes the WebSocket connection.
  Future<void> close([int? code, String? reason]) {
    return webSocket.close(code, reason);
  }
}

/// Interface for handling WebSocket events.
abstract class WebSocketHandler {
  /// Called when a WebSocket connection is established.
  FutureOr<void> onOpen(WebSocketContext context);

  /// Called when a message is received on the WebSocket.
  FutureOr<void> onMessage(WebSocketContext context, dynamic message);

  /// Called when the WebSocket connection is closed.
  FutureOr<void> onClose(WebSocketContext context);

  /// Called when an error occurs on the WebSocket connection.
  FutureOr<void> onError(WebSocketContext context, dynamic error);
}
