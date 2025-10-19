import 'dart:async';

import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = Engine()
    ..get('/', (ctx) {
      ctx.response.headers.set(HttpHeaders.contentTypeHeader, 'text/html');
      return ctx.response..write('''<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>SSE Counter</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 2rem; }
      .count { font-size: 2rem; font-weight: 600; }
      .log { margin-top: 1rem; color: #555; }
    </style>
  </head>
  <body>
    <h1>SSE Counter</h1>
    <p class="count" id="count">waiting...</p>
    <div class="log" id="log">connecting…</div>
    <script>
      const countEl = document.getElementById('count');
      const logEl = document.getElementById('log');
      const source = new EventSource('/events');

      source.addEventListener('open', () => {
        logEl.textContent = 'Connected to /events';
        console.log('SSE connected');
      });

      // Handle the initial connection event
      source.addEventListener('connected', (event) => {
        logEl.textContent = 'Connection established: ' + event.data;
        console.log('Connection event:', event.data);
      });

      source.onmessage = (event) => {
        // Only update counter for numeric data
        if (!isNaN(event.data)) {
          countEl.textContent = event.data;
          logEl.textContent = 'Last update: ' + new Date().toLocaleTimeString();
        }
        console.log('Received event', event.data);
      };

      source.onerror = (event) => {
        logEl.textContent = 'Connection lost; attempting to reconnect...';
        console.warn('SSE connection error', event);
        console.log('ReadyState:', source.readyState);
      };
    </script>
  </body>
</html>
''');
    })
    ..get('/events', (ctx) async {
      print(
        '[example] accepted SSE connection from '
        '${ctx.request.httpRequest.connectionInfo?.remoteAddress.address}',
      );

      // Add CORS headers for cross-origin requests
      ctx.response.headers.set('Access-Control-Allow-Origin', '*');
      ctx.response.headers.set('Access-Control-Allow-Headers', 'Cache-Control');

      // Create an async stream generator instead of using StreamController
      Stream<SseEvent> eventStream() async* {
        // Send initial connection event immediately
        yield SseEvent(
          id: 'init',
          event: 'connected',
          data: 'Connection established',
          retry: const Duration(seconds: 3),
        );

        var counter = 0;
        while (true) {
          await Future.delayed(const Duration(seconds: 1));
          yield SseEvent(
            id: '$counter',
            data: '$counter',
            retry: const Duration(seconds: 3),
          );
          counter++;
        }
      }

      await ctx.sse(
        eventStream(),
        heartbeat: const Duration(seconds: 15),
        heartbeatComment: 'still-alive',
      );
      print('[example] SSE handler completed');
    });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
