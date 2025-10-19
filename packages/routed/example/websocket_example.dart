import 'package:routed/routed.dart';

/// Example WebSocket handler implementation
class ChatWebSocketHandler extends WebSocketHandler {
  @override
  Future<void> onOpen(WebSocketContext context) async {
    print('New client connected');
    context.send('Welcome to the chat!');
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    print('Received message: $message');
    // Echo the message back to the client
    context.send('Server received: $message');
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    print('Client disconnected');
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    print('Error occurred: $error');
  }
}

void main() async {
  final engine = Engine();

  // Register HTTP routes
  engine.get('/', (ctx) => ctx.string('WebSocket Chat Example'));

  // Register WebSocket handler
  engine.ws('/chat', ChatWebSocketHandler());

  print('Server starting on http://localhost:3000');
  print('WebSocket endpoint available at ws://localhost:3000/chat');

  await engine.serve(port: 3000);
}

/* Example JavaScript client code:
const ws = new WebSocket('ws://localhost:3000/chat');

ws.onopen = () => {
  console.log('Connected to server');
};

ws.onmessage = (event) => {
  console.log('Received:', event.data);
};

ws.onclose = () => {
  console.log('Disconnected from server');
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

// Send a message
ws.send('Hello, server!');
*/
