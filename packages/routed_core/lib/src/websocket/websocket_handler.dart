import 'dart:async';
import 'dart:io';

import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/http/transport.dart';

/// Adapter around Dart's native WebSocket implementation.
final class IoRoutedWebSocket implements RoutedWebSocket {
  /// Creates a [IoRoutedWebSocket].
  IoRoutedWebSocket(this.socket);

  /// The socket value.
  final WebSocket socket;

  @override
  Stream<dynamic> get stream => socket;

  @override
  int? get closeCode => socket.closeCode;

  @override
  void add(dynamic data) => socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) => socket.close(code, reason);
}

/// Represents the context for a WebSocket connection.
class WebSocketContext {
  /// Creates a [WebSocketContext].
  WebSocketContext(this.webSocket, this.initialContext);

  /// The underlying host-neutral WebSocket connection.
  final RoutedWebSocket webSocket;

  /// The initial HTTP context from the upgrade request.
  final EngineContext initialContext;

  /// Sends data over the WebSocket.
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

  /// Called when an error occurs on the WebSocket.
  FutureOr<void> onError(WebSocketContext context, dynamic error);
}
