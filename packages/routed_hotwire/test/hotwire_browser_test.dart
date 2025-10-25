import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:path/path.dart' as p;

import '../example/todo_app/main.dart' as todo_app;

Future<void> main() async {
  final chatEngine = await _createChatEngine();
  final chatHandler = RoutedRequestHandler(chatEngine, true);
  final chatPort = await chatHandler.startServer(port: 0);
  final chatBaseUrl = 'http://127.0.0.1:$chatPort';

  final exampleRoot = Directory(
    p.join(
      Directory.current.path,
      'example',
      'todo_app',
    ),
  );
  if (!exampleRoot.existsSync()) {
    throw StateError('Todo example assets missing at ${exampleRoot.path}');
  }

  final todoEngine = await todo_app.createTodoApp(root: exampleRoot);
  final todoHandler = RoutedRequestHandler(todoEngine, true);
  final todoPort = await todoHandler.startServer(port: 0);
  final todoBaseUrl = 'http://127.0.0.1:$todoPort';

  await testBootstrap(
    BrowserConfig(
      browserName: 'chromium',
      headless: true,
      timeout: const Duration(seconds: 60),
    ),
  );

  tearDownAll(() async {
    await chatHandler.close();
    await todoHandler.close();
  });

  browserTest(
    'Turbo form submission updates message list',
    (browser) async {
      await browser.visit('/chat');
      await browser.waiter.waitForElement('turbo-frame#messages');

      await browser.type('input[name="text"]', 'Hello from browserTest');
      await browser.click('button[type="submit"]');

      await browser.waiter.waitForElement('#message_1');
      await browser.assertSee('Hello from browserTest');
    },
    baseUrl: chatBaseUrl,
    timeout: const Duration(minutes: 2),
  );

  browserTest(
    'Todo demo streams updates across clients',
    (browser) async {
      final config = (browser as dynamic).config;
      final baseUri = Uri.parse(config.baseUrl as String);
      final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
      final signedTopic = signTurboStreamName(const ['todos']);
      final wsUri = Uri.parse(
        '$wsScheme://${baseUri.authority}/ws/todos?topic=${Uri.encodeComponent(signedTopic)}',
      );
      final socket = await WebSocket.connect(wsUri.toString());
      final messages = <String>[];
      final subscription = socket.listen((data) {
        if (data is String) {
          messages.add(data);
        }
      });
      var messageIndex = 0;

      try {
        await browser.visit('/');
        await browser.waiter.waitForElement('turbo-frame#todo_list');
        await browser.waitUntil(() async {
          final html = await browser.getPageSource();
          return html.contains('Routed Todos');
        });

        await browser.click(
          'turbo-frame#todo_list a.todo-link[href="/todos/1"]',
        );
        await browser.waitUntil(() async {
          final html = await browser.getPageSource();
          return html.contains('Delete task');
        });

        await browser.type(
          'turbo-frame#todo_form input[name="title"]',
          'Browser todo',
        );
        await browser.type(
          'turbo-frame#todo_form textarea[name="notes"]',
          'from test',
        );
        await browser.click('turbo-frame#todo_form button[type="submit"]');

        late final ({String message, int nextIndex}) creationMessage;
        try {
          creationMessage = await _waitForMessage(
            messages,
            messageIndex,
            (message) => message.contains('Browser todo'),
          );
        } on TimeoutException catch (_) {
          fail(
            'Timed out waiting for create Turbo Stream. Messages: $messages',
          );
        }
        messageIndex = creationMessage.nextIndex;
        expect(creationMessage.message, contains('Browser todo'));

        await browser.waitUntil(() async {
          final html = await browser.getPageSource();
          return html.contains('Browser todo');
        });

        await browser.click(
          'turbo-frame#todo_list li.is-selected form[action\$="/toggle"] button',
        );

        late final ({String message, int nextIndex}) toggleMessage;
        try {
          toggleMessage = await _waitForMessage(
            messages,
            messageIndex,
            (message) => message.contains('Mark as active'),
          );
        } on TimeoutException catch (_) {
          fail(
            'Timed out waiting for toggle Turbo Stream. Messages: $messages',
          );
        }
        messageIndex = toggleMessage.nextIndex;
        expect(toggleMessage.message, contains('Mark as active'));

        await browser.waitUntil(() async {
          final html = await browser.getPageSource();
          return html.contains('Mark as active');
        });
      } finally {
        await subscription.cancel();
        await socket.close();
      }
    },
    baseUrl: todoBaseUrl,
    timeout: const Duration(minutes: 2),
  );
}

Future<Engine> _createChatEngine() async {
  final hub = TurboStreamHub();
  final messages = <ChatMessage>[];

  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
  );

  engine.get('/chat', (ctx) async {
    final turbo = ctx.turbo;
    if (turbo.kind == TurboRequestKind.stream) {
      return ctx.turboStream(
        turboStreamReplace(target: 'messages', html: _renderMessages(messages)),
      );
    }

    return ctx.turboHtml(_renderPage(messages));
  });

  engine.post('/chat/messages', (ctx) async {
    final text = (await ctx.postForm('text')).trim();
    if (text.isEmpty) {
      return ctx.turboUnprocessable(
        '<p data-turbo-temporary>Please enter a message.</p>',
      );
    }

    final message = ChatMessage(
      id: messages.length + 1,
      body: text,
      postedAt: DateTime.now(),
    );
    messages.add(message);

    final fragments = <String>[];
    if (messages.length == 1) {
      fragments.add(turboStreamRemove(target: 'empty-state'));
    }
    fragments.add(
      turboStreamAppend(target: 'messages', html: _renderMessage(message)),
    );

    if (ctx.turbo.isStreamRequest) {
      return ctx.turboStream(fragments);
    }

    hub.broadcast('chat', fragments);
    return ctx.turboSeeOther('/chat');
  });

  engine.ws(
    '/ws',
    TurboStreamSocketHandler(hub: hub, topicResolver: (_) => const ['chat']),
  );

  await engine.initialize();
  return engine;
}

class ChatMessage {
  ChatMessage({required this.id, required this.body, required this.postedAt});

  final int id;
  final String body;
  final DateTime postedAt;
}

String _renderPage(List<ChatMessage> messages) {
  return '''
<!doctype html>
<html data-turbo="true">
<head>
  <meta charset="utf-8">
  <title>routed_hotwire browser test</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017-umd.js"></script>
  <script type="module">
    const socket = new WebSocket('ws://' + location.host + '/ws');
    socket.addEventListener('message', (event) => Turbo.renderStreamMessage(event.data));
  </script>
</head>
<body>
  <main>
    <h1>Browser Test Chat</h1>
    <turbo-frame id="messages">
      ${_renderMessages(messages)}
    </turbo-frame>
    <form action="/chat/messages" method="post">
      <label>
        <span>Message</span>
        <input type="text" name="text" autocomplete="off" required>
      </label>
      <button type="submit">Send</button>
    </form>
  </main>
</body>
</html>
''';
}

String _renderMessages(List<ChatMessage> messages) {
  if (messages.isEmpty) {
    return '<p id="empty-state">No messages yet.</p>';
  }
  return messages.map(_renderMessage).join();
}

String _renderMessage(ChatMessage message) {
  final escapedBody = htmlEscape.convert(message.body);
  final timestamp = htmlEscape.convert(message.postedAt.toIso8601String());
  return '''
<div class="msg" id="message_${message.id}">
  <span class="body">$escapedBody</span>
  <time datetime="$timestamp">${message.postedAt.toLocal()}</time>
</div>
''';
}

Future<({String message, int nextIndex})> _waitForMessage(
  List<String> messages,
  int startIndex,
  bool Function(String message) predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  var index = startIndex;
  while (DateTime.now().isBefore(deadline)) {
    while (index < messages.length) {
      final message = messages[index];
      index += 1;
      if (predicate(message)) {
        return (message: message, nextIndex: index);
      }
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Timed out waiting for Turbo Stream message', timeout);
}
