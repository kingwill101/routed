import 'dart:collection';

import 'package:routed/routed.dart';

import '../turbo_stream_name.dart';
import '../turbo_streams.dart';

/// Minimal contract representing a client connection that can receive Turbo Streams.
abstract class TurboStreamConnection {
  int? get closeCode;

  void send(String payload);
}

class WebSocketTurboConnection implements TurboStreamConnection {
  WebSocketTurboConnection(this.context);

  final WebSocketContext context;

  @override
  int? get closeCode => context.webSocket.closeCode;

  @override
  void send(String payload) => context.send(payload);
}

typedef TurboTopicResolver =
    Iterable<String> Function(WebSocketContext context);

/// Topic-based broadcaster for Turbo Stream fragments.
class TurboStreamHub {
  final _topics = <String, LinkedHashSet<TurboStreamConnection>>{};
  final _connectionTopics = <TurboStreamConnection, Set<String>>{};

  /// Subscribe [connection] to the provided [topics].
  void subscribe(TurboStreamConnection connection, Iterable<String> topics) {
    final normalized = topics
        .map((topic) => topic.trim())
        .where((topic) => topic.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return;

    for (final topic in normalized) {
      final set = _topics.putIfAbsent(
        topic,
        () => LinkedHashSet<TurboStreamConnection>(),
      );
      set.add(connection);
    }

    final current = _connectionTopics.putIfAbsent(connection, () => <String>{});
    current.addAll(normalized);
  }

  /// Remove [connection] from all topics or the provided subset.
  void unsubscribe(
    TurboStreamConnection connection, {
    Iterable<String>? topics,
  }) {
    final ownedTopics = _connectionTopics[connection];
    if (ownedTopics == null) return;

    final toRemove = topics == null
        ? ownedTopics.toList()
        : topics.map((t) => t.trim());

    for (final topic in toRemove) {
      if (topic.isEmpty) continue;
      final subscribers = _topics[topic];
      subscribers?.remove(connection);
      if (subscribers != null && subscribers.isEmpty) {
        _topics.remove(topic);
      }
      ownedTopics.remove(topic);
    }

    if (ownedTopics.isEmpty) {
      _connectionTopics.remove(connection);
    }
  }

  /// Broadcast [fragments] to every subscriber of [topic].
  void broadcast(String topic, Iterable<String> fragments) {
    final payload = normalizeTurboStreamBody(fragments);
    if (payload.isEmpty) return;

    final subscribers = _topics[topic];
    if (subscribers == null || subscribers.isEmpty) return;

    final disconnected = <TurboStreamConnection>[];
    for (final connection in subscribers) {
      try {
        if (connection.closeCode != null) {
          disconnected.add(connection);
          continue;
        }
        connection.send(payload);
      } catch (_) {
        disconnected.add(connection);
      }
    }

    for (final connection in disconnected) {
      unsubscribe(connection);
    }
  }
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

Iterable<String> _defaultTopicResolver(WebSocketContext context) {
  final uri = context.initialContext.request.uri;
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
