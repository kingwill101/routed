// ignore_for_file: unnecessary_import

import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:routed_sessions/routed_sessions.dart';

void main(List<String> args) async {
  // Construct an Engine instance with a secure cookie-backed session store.
  final engine = Engine(
    providers: [
      ...Engine.defaultProviders,
      RoutedSessionsProvider(
        SessionConfig(
          store: CookieStore(
            defaultOptions: SessionOptions(
              path: '/',
              maxAge: 3600, // 1 hour
              secure: false,
              httpOnly: true,
            ),
            codecs: [
              SecureCookie(
                useEncryption: true,
                useSigning: true,
                key:
                    'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
              ),
            ],
          ),
          cookieName: 'routed_session',
        ),
      ),
    ],
  );
  engine.addGlobalMiddleware(sessionMiddleware());

  // Example route: increments a session counter each time it's visited
  engine.get('/counter', (ctx) {
    final currentCount = ctx.getSession<int>('count') ?? 0;
    ctx.setSession('count', currentCount + 1);
    ctx.string('Counter = ${currentCount + 1}');
  });

  // Example route: reset the session
  engine.get('/reset', (ctx) {
    ctx.clearSession();
    ctx.string('Session reset');
  });

  // Start the server on localhost:8080
  await engine.serve(host: '127.0.0.1', port: 8080);
}
