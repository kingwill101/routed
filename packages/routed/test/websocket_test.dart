import 'dart:io';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket Tests', () {
    late Engine engine;
    late HttpServer server;

    setUp(() async {
      engine = Engine();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => engine.handleRequest(request));
    });

    tearDown(() async {
      await server.close();
    });

    test('WebSocket connection and message exchange', () async {
      final List<String> serverMessages = [];
      final List<String> clientMessages = [];

      engine.ws(
        '/chat',
        TestWebSocketHandler(
          onMessage: (ctx, msg) {
            serverMessages.add(msg.toString());
            ctx.send('Server received: $msg');
          },
        ),
      );

      final ws = await WebSocket.connect('ws://localhost:${server.port}/chat');

      ws.listen((message) {
        clientMessages.add(message.toString());
      });

      ws.add('Hello Server');

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(serverMessages, contains('Hello Server'));
      expect(clientMessages, contains('Server received: Hello Server'));

      await ws.close();
    });

    test('WebSocket connection rejection for invalid path', () async {
      engine.ws('/valid', TestWebSocketHandler());

      expect(
        () => WebSocket.connect('ws://localhost:${server.port}/invalid'),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('WebSocket handler lifecycle events', () async {
      final events = <String>[];

      engine.ws(
        '/lifecycle',
        TestWebSocketHandler(
          onOpen: (ctx) => events.add('open'),
          onClose: (ctx) => events.add('close'),
        ),
      );

      final ws = await WebSocket.connect(
        'ws://localhost:${server.port}/lifecycle',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await ws.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, ['open', 'close']);
    });
  });
}

/// Test WebSocket handler with configurable callbacks
class TestWebSocketHandler extends WebSocketHandler {
  final void Function(WebSocketContext)? _handleOpen;
  final void Function(WebSocketContext, dynamic)? _handleMessage;
  final void Function(WebSocketContext)? _handleClose;
  final void Function(WebSocketContext, dynamic)? _handleError;

  TestWebSocketHandler({
    void Function(WebSocketContext)? onOpen,
    void Function(WebSocketContext, dynamic)? onMessage,
    void Function(WebSocketContext)? onClose,
    void Function(WebSocketContext, dynamic)? onError,
  }) : _handleOpen = onOpen,
       _handleMessage = onMessage,
       _handleClose = onClose,
       _handleError = onError;

  @override
  Future<void> onOpen(WebSocketContext context) async {
    _handleOpen?.call(context);
  }

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {
    _handleMessage?.call(context, message);
  }

  @override
  Future<void> onClose(WebSocketContext context) async {
    _handleClose?.call(context);
  }

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {
    _handleError?.call(context, error);
  }
}
