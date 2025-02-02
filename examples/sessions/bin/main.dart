import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/middlewares.dart';

void main(List<String> args) async {
  // Create a secure cookie store with a random or fixed hash key
  final store = CookieStore(
    codecs: [
      SecureCookie([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
    ],
    defaultOptions: Options(
      path: '/',
      maxAge: 3600, // 1 hour
      secure: false,
      httpOnly: true,
    ),
  );

  // Construct an Engine instance
  final engine = Engine();
  // Add the session middleware globally
  engine.middlewares
      .add(sessionMiddleware(store)); // from your session.dart middleware

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
