import 'dart:collection';

import 'package:routed/routed.dart';
import 'package:routed_hotwire/src/websocket/stream_connection.dart';

import '../turbo_streams.dart';

class WebSocketTurboConnection implements TurboStreamConnection {
  WebSocketTurboConnection(this.context);

  final WebSocketContext context;

  @override
  int? get closeCode => context.webSocket.closeCode;

  @override
  void send(String payload) => context.send(payload);
}

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
