// WebSocket wrapper for routed_http per refactor.md §11.
// Core upgrade stays in routed; this provides a routed_http-owned facade.
import 'dart:io';

import 'websocket_handler.dart';

/// Lightweight wrapper that upgrades an incoming [HttpRequest] to a
/// WebSocket connection and delegates to a [WebSocketHandler].
class RoutedWebSocket {
  final WebSocketHandler handler;
  RoutedWebSocket(this.handler);
  Future<void> upgrade(HttpRequest request) async {}
}
