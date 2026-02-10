// WebSocket Example
//
// Demonstrates two patterns for WebSocket handling in the routed framework:
//
//   1. Echo handler  — echoes every message back to the sender
//   2. Chat handler  — broadcasts messages to all connected clients
//
// Run the server:
//   dart run bin/server.dart
//
// Then run the client to exercise both endpoints:
//   dart run bin/client.dart
import 'dart:io';

import 'package:routed/routed.dart';

// ---------------------------------------------------------------------------
// 1. Echo handler — the simplest possible WebSocket handler.
//    Every message is sent straight back to the same client.
// ---------------------------------------------------------------------------

class EchoHandler extends WebSocketHandler {
  @override
  Future<void> onOpen(WebSocketContext context) async {
    print('[echo] client connected');
    context.send('Connected to echo server');
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    print('[echo] received: $message');
    context.send('echo: $message');
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    print('[echo] client disconnected');
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    print('[echo] error: $error');
  }
}

// ---------------------------------------------------------------------------
// 2. Chat handler — multi-client chat room.
//    Messages are broadcast to every connected client.
//    Supports /nick <name> to change display name.
// ---------------------------------------------------------------------------

class _Client {
  _Client(this.id, this.context, this.name);

  final String id;
  final WebSocketContext context;
  String name;
}

class ChatHandler extends WebSocketHandler {
  final Map<String, _Client> _clients = {};

  @override
  Future<void> onOpen(WebSocketContext context) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final client = _Client(id, context, 'User#$id');
    _clients[id] = client;

    context.send('Welcome, ${client.name}! (${_clients.length} online)');
    _broadcast('${client.name} joined', excludeId: id);
    print('[chat] ${client.name} joined (${_clients.length} online)');
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    final client = _findClient(context);
    if (client == null) return;

    if (message is String && message.startsWith('/nick ')) {
      final newName = message.substring(6).trim();
      if (newName.isNotEmpty) {
        final oldName = client.name;
        client.name = newName;
        _broadcast('$oldName is now known as $newName');
        print('[chat] $oldName -> $newName');
      }
      return;
    }

    print('[chat] ${client.name}: $message');
    _broadcast('${client.name}: $message');
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    final client = _findClient(context);
    if (client != null) {
      _clients.remove(client.id);
      _broadcast('${client.name} left');
      print('[chat] ${client.name} left (${_clients.length} online)');
    }
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    print('[chat] error: $error');
    final client = _findClient(context);
    if (client != null) {
      _clients.remove(client.id);
      _broadcast('${client.name} disconnected (error)');
    }
  }

  _Client? _findClient(WebSocketContext context) {
    return _clients.values.where((c) => c.context == context).firstOrNull;
  }

  void _broadcast(String message, {String? excludeId}) {
    for (final client in _clients.values) {
      if (client.id != excludeId) {
        client.context.send(message);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 3. Parameterised handler — demonstrates path parameters on WS routes.
//    The room name is extracted from the URL.
// ---------------------------------------------------------------------------

class RoomHandler extends WebSocketHandler {
  final Map<String, Set<WebSocketContext>> _rooms = {};

  String _room(WebSocketContext context) =>
      context.initialContext.param('room') ?? 'default';

  @override
  Future<void> onOpen(WebSocketContext context) async {
    final room = _room(context);
    _rooms.putIfAbsent(room, () => {}).add(context);
    context.send('Joined room "$room" (${_rooms[room]!.length} members)');
    print('[room:$room] +1 (${_rooms[room]!.length} members)');
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    final room = _room(context);
    final members = _rooms[room] ?? {};
    for (final member in members) {
      if (member != context) {
        member.send(message);
      }
    }
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    final room = _room(context);
    _rooms[room]?.remove(context);
    print('[room:$room] -1 (${_rooms[room]?.length ?? 0} members)');
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    final room = _room(context);
    _rooms[room]?.remove(context);
    print('[room:$room] error: $error');
  }
}

// ---------------------------------------------------------------------------
// Server entry point
// ---------------------------------------------------------------------------

void main() async {
  final engine = Engine();

  // Health check
  engine.get('/health', (ctx) => ctx.json({'status': 'ok'}));

  // WebSocket routes
  engine.ws('/echo', EchoHandler());
  engine.ws('/chat', ChatHandler());
  engine.ws('/rooms/{room}', RoomHandler());

  await engine.serve(port: 3000, echo: true);
  print('WebSocket example running at http://localhost:3000');
  print('');
  print('Endpoints:');
  print('  ws://localhost:3000/echo          — echo server');
  print('  ws://localhost:3000/chat          — chat room');
  print('  ws://localhost:3000/rooms/{room}  — named rooms');
  print('');
  print('Run "dart run bin/client.dart" to exercise all endpoints');

  ProcessSignal.sigint.watch().listen((_) async {
    await engine.close();
    exit(0);
  });
}
