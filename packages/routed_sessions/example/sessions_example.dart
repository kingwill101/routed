import 'package:routed_core/routed_core.dart' hide SecureCookie;
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_sessions/server_sessions.dart';

void main() async {
  final store = MemorySessionStore(
    codecs: [SecureCookie(useEncryption: false, useSigning: false)],
    defaultOptions: SessionOptions(path: '/', httpOnly: true),
    lifetime: Duration(hours: 2),
  );
  final engine = Engine();
  // sessionMiddleware is a Middleware: use via Engine.use or route middlewares
  engine.get('/', (ctx) {
    ctx.setSession('visits', (ctx.getSession<int>('visits') ?? 0) + 1);
    return ctx.json({'visits': ctx.getSession('visits'), 'id': ctx.sessionId});
  }, middlewares: [sessionMiddleware(store)]);

  engine.get('/destroy', (ctx) {
    ctx.destroySession();
    return ctx.json({'destroyed': true});
  }, middlewares: [sessionMiddleware(store)]);

  print('routed_sessions example: GET / and GET /destroy');
  await engine.close();
}
