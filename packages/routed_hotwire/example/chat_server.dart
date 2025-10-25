import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

final hub = TurboStreamHub();
final rooms = <String, List<ChatMessage>>{};
int _messageId = 0;

Future<void> main() async {
  final engine = Engine();

  engine.get('/rooms/{id}', showRoom);
  engine.post('/rooms/{id}/messages', createMessage);

  engine.ws('/ws', TurboStreamSocketHandler(hub: hub));

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
  stdout.writeln(
    'Hotwire demo listening on http://localhost:$port/rooms/lobby',
  );
  await engine.serve(port: port);
}

Future<Response> showRoom(EngineContext ctx) async {
  final roomId = ctx.request.pathParameters['id']?.toString() ?? 'lobby';
  final messages = rooms.putIfAbsent(roomId, () => <ChatMessage>[]);
  final turbo = ctx.turbo;

  if (turbo.kind == TurboRequestKind.stream) {
    // Streams typically aren't fetched directly for GET routes, but supporting
    // the branch keeps the example symmetrical with POST handlers.
    return ctx.turboStream(
      turboStreamReplace(target: 'messages', html: renderMessageList(messages)),
    );
  }

  if (turbo.kind == TurboRequestKind.frame) {
    if (turbo.frameId == 'messages') {
      return ctx.turboFrame(renderMessageList(messages));
    }
    if (turbo.frameId == 'composer') {
      return ctx.turboFrame(renderComposer(roomId));
    }
  }

  return ctx.turboHtml(renderPage(ctx, roomId, messages));
}

Future<Response> createMessage(EngineContext ctx) async {
  final roomId = ctx.request.pathParameters['id']?.toString() ?? 'lobby';
  final messages = rooms.putIfAbsent(roomId, () => <ChatMessage>[]);
  final text = (await ctx.postForm('text')).trim();

  if (text.isEmpty) {
    return ctx.turboUnprocessable(
      '<p data-turbo-temporary>Please enter a message.</p>',
    );
  }

  final message = ChatMessage(
    id: ++_messageId,
    roomId: roomId,
    body: text,
    postedAt: DateTime.now(),
  );
  messages.add(message);

  final fragment = turboStreamAppend(
    target: 'messages',
    html: renderMessage(message),
  );
  hub.broadcast('room:$roomId', [fragment]);

  if (ctx.turbo.isStreamRequest) {
    return ctx.turboStream(fragment);
  }

  return ctx.turboSeeOther('/rooms/$roomId');
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.body,
    required this.postedAt,
  });

  final int id;
  final String roomId;
  final String body;
  final DateTime postedAt;
}

String renderPage(
  EngineContext ctx,
  String roomId,
  List<ChatMessage> messages,
) {
  final csrfName = ctx.engineConfig.security.csrfCookieName;
  String csrfToken = '';
  try {
    csrfToken = ctx.getSession<String>(csrfName) ?? '';
  } catch (_) {
    csrfToken = '';
  }
  final wsProtocol = ctx.request.uri.scheme == 'https' ? 'wss' : 'ws';
  return '''
<!doctype html>
<html data-turbo="true">
<head>
  <meta charset="utf-8">
  <title>routed + Hotwire lobby</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="csrf-token" content="$csrfToken">
  <link rel="stylesheet" href="https://fonts.cdnfonts.com/css/inter">
  <script src="https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017-umd.js"></script>
  <script type="module">
    const roomId = '$roomId';
    document.addEventListener('turbo:before-fetch-request', (event) => {
      const token = document.querySelector('meta[name="csrf-token"]')?.content;
      if (token) {
        event.detail.fetchOptions.headers['X-CSRF-Token'] = token;
      }
    });

    const turbo = window.Turbo;
    const socket = new WebSocket(
      '$wsProtocol://' + window.location.host + '/ws?topic=room:' + roomId,
    );
    socket.addEventListener('message', (event) => {
      if (turbo) {
        turbo.renderStreamMessage(event.data);
      }
    });
  </script>
  <style>
    body {
      font-family: "Inter", system-ui, sans-serif;
      margin: 0;
      padding: 0;
      background: #111827;
      color: #f9fafb;
      display: grid;
      place-items: center;
      min-height: 100vh;
    }
    main {
      width: min(40rem, 100vw - 2rem);
      display: grid;
      gap: 1rem;
      padding: 1.5rem;
      background: rgba(15, 23, 42, 0.85);
      border-radius: 1rem;
      box-shadow: 0 25px 50px -12px rgba(30, 64, 175, 0.45);
      backdrop-filter: blur(12px);
    }
    h1 {
      margin: 0;
      font-weight: 600;
      font-size: 1.5rem;
      letter-spacing: 0.01em;
    }
    .msg {
      border-radius: 0.75rem;
      padding: 0.75rem 1rem;
      background: rgba(79, 70, 229, 0.15);
      border: 1px solid rgba(129, 140, 248, 0.25);
      margin-bottom: 0.75rem;
      line-height: 1.4;
    }
    .msg time {
      display: block;
      font-size: 0.75rem;
      opacity: 0.6;
      margin-top: 0.35rem;
    }
    form {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 0.75rem;
    }
    input[type="text"] {
      background: rgba(30, 64, 175, 0.18);
      border: 1px solid rgba(129, 140, 248, 0.35);
      border-radius: 0.75rem;
      padding: 0.75rem 1rem;
      color: inherit;
      font-size: 1rem;
    }
    button {
      padding: 0.75rem 1.5rem;
      border-radius: 0.75rem;
      border: none;
      font-weight: 600;
      color: #0f172a;
      background: linear-gradient(135deg, #60a5fa, #c084fc);
      cursor: pointer;
    }
    button:hover {
      filter: brightness(1.05);
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Room: $roomId</h1>
      <p>Open this page in multiple tabs to see Turbo Streams update instantly.</p>
    </header>
    <turbo-frame id="messages">
      ${renderMessageList(messages)}
    </turbo-frame>
    <turbo-frame id="composer">
      ${renderComposer(roomId)}
    </turbo-frame>
  </main>
</body>
</html>
''';
}

String renderMessageList(List<ChatMessage> messages) {
  if (messages.isEmpty) {
    return '<p class="msg" id="empty">No messages yet. Be the first!</p>';
  }
  final buffer = StringBuffer();
  for (final message in messages) {
    buffer.write(renderMessage(message));
  }
  return buffer.toString();
}

String renderMessage(ChatMessage message) {
  final timestamp = message.postedAt.toIso8601String();
  return '''
<div class="msg" id="message_${message.id}">
  ${htmlEscape.convert(message.body)}
  <time datetime="$timestamp">${message.postedAt.toLocal()}</time>
</div>
''';
}

String renderComposer(String roomId) {
  return '''
<form action="/rooms/$roomId/messages" method="post">
  <input type="text" name="text" placeholder="Say something..." autocomplete="off" required>
  <button type="submit">Send</button>
</form>
''';
}

const htmlEscape = HtmlEscape();
