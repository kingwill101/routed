import 'package:routed_core/routed_core.dart' show WebSocketContext;

/// Minimal contract representing a client connection that can receive Turbo Streams.
abstract class TurboStreamConnection {
  int? get closeCode;

  void send(String payload);
}

typedef TurboTopicResolver =
    Iterable<String> Function(WebSocketContext context);
