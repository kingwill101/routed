import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';

void main() async {
  final store = MemorySessionStore(
    codecs: [SecureCookie()],
    defaultOptions: SessionOptions(httpOnly: true),
    lifetime: const Duration(hours: 2),
  );
  // sessionMiddleware is a Middleware: use via Engine.use or route middlewares
  final engine = Engine()
    ..get('/', (ctx) {
      ctx.setSession('visits', (ctx.getSession<int>('visits') ?? 0) + 1);
      return ctx.json({
        'visits': ctx.getSession<int>('visits'),
        'id': ctx.sessionId,
      });
    }, middlewares: [sessionMiddleware(store)])
    ..get('/destroy', (ctx) {
      ctx.destroySession();
      return ctx.json({'destroyed': true});
    }, middlewares: [sessionMiddleware(store)]);

  stdout.writeln('routed_sessions example: GET / and GET /destroy');
  await engine.close();
}
