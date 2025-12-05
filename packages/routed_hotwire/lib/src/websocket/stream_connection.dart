import 'package:routed/routed.dart' show WebSocketContext;

/// Minimal contract representing a client connection that can receive Turbo Streams.
abstract class TurboStreamConnection {
  int? get closeCode;

  void send(String payload);
}

typedef TurboTopicResolver =
    Iterable<String> Function(WebSocketContext context);
