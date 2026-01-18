import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

Iterable<String> _defaultTopicResolver(WebSocketContext context) {
  final uri = context.initialContext.uri;
  final rawValues = <String>[];
  final multi = uri.queryParametersAll['topic'];
  if (multi != null && multi.isNotEmpty) {
    rawValues.addAll(multi);
  } else {
    final single = uri.queryParameters['topic'];
    if (single != null) rawValues.add(single);
  }

  if (rawValues.isEmpty) return const [];

  final topics = <String>{};
  for (final raw in rawValues) {
    for (final piece in raw.split(',')) {
      final trimmed = piece.trim();
      if (trimmed.isEmpty) continue;
      final verified = verifyTurboStreamName(trimmed);
      topics.add(verified ?? trimmed);
    }
  }

  return topics;
}

/// Skeleton WebSocket handler that wires routed's built-in support to [TurboStreamHub].
class TurboStreamSocketHandler extends WebSocketHandler {
  TurboStreamSocketHandler({
    required this.hub,
    TurboTopicResolver? topicResolver,
    this.messageHandler,
  }) : topicResolver = topicResolver ?? _defaultTopicResolver;

  final TurboStreamHub hub;
  final TurboTopicResolver topicResolver;
  final Future<void> Function(WebSocketContext context, dynamic message)?
  messageHandler;
  final _connections = <WebSocketContext, TurboStreamConnection>{};

  @override
  Future<void> onOpen(WebSocketContext context) async {
    final topics = topicResolver(context);
    if (topics.isEmpty) {
      await context.close(1008, 'No turbo topics supplied');
      return;
    }
    final connection = WebSocketTurboConnection(context);
    _connections[context] = connection;
    hub.subscribe(connection, topics);
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    if (messageHandler != null) {
      await messageHandler!(context, message);
    }
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    final connection = _connections.remove(context);
    if (connection != null) {
      hub.unsubscribe(connection);
    }
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    final connection = _connections.remove(context);
    if (connection != null) {
      hub.unsubscribe(connection);
    }
  }
}
