import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:routed/session.dart';

void main(List<String> args) async {
  // Create a secure cookie store with a random or fixed hash key

  // Construct an Engine instance
  final engine = Engine(
    options: [
      withSessionConfig(
        SessionConfig(
          store: CookieStore(
            defaultOptions: Options(
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

  // Example route: increments a session counter each time it’s visited
  engine.get('/counter', (ctx) async {
    // Retrieve the session from context
    final session = ctx.get<Session>('session');
    if (session == null) {
      ctx.string('No session found');
      return;
    }

    // Increment a counter in the session
    final currentCount = (session.values['count'] ?? 0) as int;
    session.values['count'] = currentCount + 1;

    ctx.string('Counter = ${session.values['count']}');
  });

  // Example route: reset the session
  engine.get('/reset', (ctx) async {
    final session = ctx.get<Session>('session');
    if (session == null) {
      ctx.string('No session found');
      return;
    }
    session.values.clear();
    ctx.string('Session reset');
  });

  // Start the server on localhost:8080
  await engine.serve(host: '127.0.0.1', port: 8080);
}
