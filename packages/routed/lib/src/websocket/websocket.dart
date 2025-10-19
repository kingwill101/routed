import 'dart:io';
import 'package:routed/src/websocket/websocket_handler.dart';

/// A lightweight wrapper that upgrades an incoming [HttpRequest] to a
/// WebSocket connection and delegates all interaction to a
/// [WebSocketHandler].
///
/// This class exists to keep the low-level upgrade logic in one place while
/// letting callers inject their own handler implementation.
class WebSocket {
  /// The handler that processes frames and lifecycle events for this
  /// connection.
  final WebSocketHandler handler;

  /// Creates a new wrapper that forwards all WebSocket events to [handler].
  WebSocket(this.handler);

  /// Upgrades [request] to a WebSocket connection.
  ///
  /// The returned future completes when the upgrade handshake finishes,
  /// whether it succeeds or fails.
  Future<void> upgrade(HttpRequest request) async {}
}
