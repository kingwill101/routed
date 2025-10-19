import 'dart:io';

import 'package:routed/routed.dart';

/// Represents a connected chat client
class ChatClient {
  final String id;
  final WebSocketContext socket;
  String username;

  ChatClient(this.id, this.socket, this.username);
}

/// Handles WebSocket chat functionality
class ChatHandler extends WebSocketHandler {
  // Store connected clients
  final Map<String, ChatClient> _clients = {};

  @override
  Future<void> onOpen(WebSocketContext context) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final client = ChatClient(id, context, 'User$id');
    _clients[id] = client;

    // Broadcast new user joined
    _broadcast('${client.username} joined the chat', excludeId: id);

    // Send welcome message to new user
    context.send('Welcome to the chat, ${client.username}!');
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    final client = _findClient(context);
    if (client == null) return;

    if (message is String) {
      if (message.startsWith('/nick ')) {
        // Handle nickname change
        final newName = message.substring(6).trim();
        if (newName.isNotEmpty) {
          final oldName = client.username;
          client.username = newName;
          _broadcast('$oldName is now known as $newName');
        }
      } else {
        // Broadcast regular message
        _broadcast('${client.username}: $message');
      }
    }
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    final client = _findClient(context);
    if (client != null) {
      _clients.remove(client.id);
      _broadcast('${client.username} left the chat');
    }
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    print('Error occurred: $error');
    final client = _findClient(context);
    if (client != null) {
      _clients.remove(client.id);
      _broadcast('${client.username} disconnected due to an error');
    }
  }

  /// Finds a client by their WebSocket context
  ChatClient? _findClient(WebSocketContext context) {
    return _clients.values
        .where((client) => client.socket == context)
        .firstOrNull;
  }

  /// Broadcasts a message to all connected clients
  void _broadcast(String message, {String? excludeId}) {
    for (final client in _clients.values) {
      if (client.id != excludeId) {
        client.socket.send(message);
      }
    }
  }
}

void main() async {
  final engine = Engine();

  // Serve static files for the chat client
  engine.static('/', 'public');

  // Set up WebSocket endpoint
  engine.ws('/chat', ChatHandler());

  // Start the server
  await engine.serve(port: 3000);
  print('Chat server running on http://localhost:3000');

  // Close the server gracefully on shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    await engine.close();
    exit(0);
  });
}
