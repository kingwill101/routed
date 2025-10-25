# routed_hotwire

Utilities that let routed-based backends speak Hotwire. The package bundles
request helpers, response builders, and real-time broadcasting adapters so you
can reuse Turbo Drive/Frames/Streams and Stimulus with minimal ceremony.

## What’s included

- `TurboRequestInfo` for classifying incoming requests as full page, frame, or
  stream interactions.
- Response helpers that emit the correct headers for HTML, Turbo Streams,
  redirects, and validation failures.
- String builders for `<turbo-stream>` fragments.
- A small topic-based WebSocket hub and handler that sit on top of routed’s
  built-in WebSocket support.
- Documentation on wiring the existing routed CSRF middleware and SSE helpers
  into Turbo apps.

## Installation

Add the dependency to the routed workspace (already done for `routed_ecosystem`)
or to an individual package:

```yaml
dependencies:
  routed_hotwire: ^0.1.0
```

## Quick start

```dart
import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

final hub = TurboStreamHub();
final messages = <String>[];

Future<Response> showRoom(EngineContext ctx) async {
  final turbo = ctx.turbo;
  final roomId = ctx.request.pathParameters['id'] as String;

  if (turbo.isStreamRequest) {
    return ctx.turboStream(
      turboStreamAppend(
        target: 'messages',
        html: '<div class="msg">${messages.last}</div>',
      ),
    );
  }

  final page = '''
  <!doctype html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="csrf-token" content="${ctx.getSession<String>(ctx.engineConfig.security.csrfCookieName) ?? ''}">
    <script src="https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017-umd.js"></script>
    <script type="module">
      document.addEventListener('turbo:before-fetch-request', (event) => {
        const token = document.querySelector('meta[name="csrf-token"]')?.content;
        if (token) event.detail.fetchOptions.headers['X-CSRF-Token'] = token;
      });

    const wsScheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const turbo = window.Turbo;
    const socket = new WebSocket(`${wsScheme}://${window.location.host}/ws?topic=room:$roomId`);
    socket.addEventListener('message', (e) => {
      if (turbo) turbo.renderStreamMessage(e.data);
    });
    </script>
  </head>
  <body>
    <turbo-frame id="messages">
      ${messages.map((m) => '<div class="msg">$m</div>').join()}
    </turbo-frame>
    <turbo-frame id="composer">
      <form action="/rooms/$roomId/messages" method="post">
        <input type="text" name="text" autocomplete="off">
        <button>Send</button>
      </form>
    </turbo-frame>
  </body>
  </html>
  ''';

  return ctx.turboHtml(page);
}

Future<Response> createMessage(EngineContext ctx) async {
  final roomId = ctx.request.pathParameters['id'] as String;
  final text = (await ctx.postForm('text')).trim();
  if (text.isEmpty) {
    return ctx.turboUnprocessable('<p data-turbo-temporary>Please enter text.</p>');
  }

  messages.add(text);
  hub.broadcast(
    'room:$roomId',
    [
      turboStreamAppend(
        target: 'messages',
        html: '<div class="msg">$text</div>',
      ),
    ],
  );

  return ctx.turboSeeOther('/rooms/$roomId');
}

void main() async {
  final engine = Engine();
  engine.get('/rooms/{id}', showRoom);
  engine.post('/rooms/{id}/messages', createMessage);
  engine.ws(
    '/ws',
    TurboStreamSocketHandler(hub: hub),
  );
  await engine.serve(port: 3000);
}
```

### Turbo request helpers

```dart
final turbo = ctx.turbo;
switch (turbo.kind) {
  case TurboRequestKind.stream:
    // Return text/vnd.turbo-stream.html
    break;
  case TurboRequestKind.frame:
    // Return partial HTML without layout
    break;
  case TurboRequestKind.standard:
    // Fall back to traditional HTML
    break;
}
```

### Turbo Streams

Use the builders to render fragments and `TurboResponse.stream` (or the
`ctx.turboStream` extension) to send them:

```dart
final fragment = turboStreamReplace(
  target: 'message_${message.id}',
  html: renderMessageHtml(message),
);
ctx.turboStream(fragment);
```

You can combine multiple fragments before returning:

```dart
ctx.turboStream(joinTurboStreams([
  turboStreamRemove(target: 'message_${old.id}'),
  turboStreamAppend(target: 'messages', html: renderMessageHtml(newer)),
]));
```

### CSRF integration

The routed CSRF middleware issues tokens on safe requests and stores them in
`ctx.engineConfig.security.csrfCookieName` (default `csrf_token`).

- Render the token into a `<meta name="csrf-token">` tag.
- Add a small script to copy the token into Turbo’s `fetchOptions.headers`:

```html
<script type="module">
document.addEventListener('turbo:before-fetch-request', (event) => {
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  if (token) event.detail.fetchOptions.headers['X-CSRF-Token'] = token;
});
</script>
```

That is enough for routed’s existing middleware to reject state-changing
requests that are missing or spoofing the token.

### Broadcasting Turbo streams

`TurboStreamHub` maintains topic → WebSocketContext subscriptions and surfaces a
simple API:

```dart
final hub = TurboStreamHub();

engine.ws(
  '/ws',
  TurboStreamSocketHandler(
    hub: hub,
    // Optional: customise topic resolution
    topicResolver: (ctx) =>
        [ctx.initialContext.request.uri.queryParameters['room'] ?? 'lobby'],
  ),
);

hub.broadcast(
  'room:lobby',
  turboStreamAppend(target: 'messages', html: renderMessage(msg)),
);
```

Clients can subscribe by connecting to `ws://host/ws?topic=room:lobby`. The hub
filters closed sockets automatically. If you prefer Server-Sent Events, reuse
`ctx.sse` and feed the fragments to `Turbo.renderStreamMessage` on the client –
the README example shows both approaches.

### Testing guidance

Use `routed_testing` to exercise Turbo flows without spinning up a full server:

```dart
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  engineTest('returns stream response for Turbo requests', (engine, client) async {
    engine.post('/widgets', (ctx) {
      return ctx.turboStream(turboStreamAppend(
        target: 'widgets',
        html: '<div id="widget_1">hello</div>',
      ));
    });

    final response = await client.post(
      '/widgets',
      headers: {'Accept': 'text/vnd.turbo-stream.html'},
    );

    response
      .assertStatus(200)
      .assertHeader('content-type', contains('text/vnd.turbo-stream.html'));
  });
}
```

For end-to-end validation use Playwright or WebDriver to load your routed
application with Turbo enabled, submit forms inside `<turbo-frame>` elements,
and assert that the DOM updates without a full page refresh.
The package’s test suite includes a `browserTest` that drives a headless
Chromium session against the built-in chat demo to verify Turbo-in-the-browser
behaviour.

## Stimulus scaffolding

Need Stimulus in the browser as well? Scaffold a starter setup with the routed
CLI:

```bash
dart run routed_cli stimulus:install
```

This command creates `public/js/stimulus.js` alongside
`public/js/controllers/` (with an `application.js`, `index.js`, and sample
`hello_controller.js`). Add the generated loader to your base layout:

```html
<script type="module" src="/js/stimulus.js"></script>
```

Register additional controllers inside
`public/js/controllers/index.js`, then attach them in your templates with
`data-controller` attributes.

## Example applications

- **Realtime chat** — `example/chat_server.dart`  
  ```bash
  dart run packages/routed_hotwire/example/chat_server.dart
  ```  
  Visit http://localhost:3000/rooms/lobby in multiple tabs to watch Turbo Stream
  broadcasts update every window.

- **Todo dashboard** — `example/todo_app/main.dart`  
  ```bash
  dart run packages/routed_hotwire/example/todo_app/main.dart
  ```  
  This multi-page demo renders Liquid templates, serves static JavaScript from
  disk, and uses Turbo Frames/Streams to keep the list, detail panel, and form
  in sync across browser windows at http://localhost:4000/.
