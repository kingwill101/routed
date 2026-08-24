import 'package:routed_core/routed_core.dart' show WebSocketContext;

/// Minimal contract for a client connection that receives Turbo Streams.
abstract class TurboStreamConnection {
  /// The WebSocket close code, or `null` while the connection is open.
  int? get closeCode;

  /// Sends a Turbo Stream payload to the client.
  void send(String payload);
}

/// Resolves the Turbo topics that should receive a WebSocket connection.
typedef TurboTopicResolver =
    Iterable<String> Function(WebSocketContext context);
