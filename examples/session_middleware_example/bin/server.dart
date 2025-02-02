import 'dart:convert';
import 'package:routed/routed.dart';
import 'package:routed/src/middleware/session.dart';
import 'package:routed/src/sessions/cookie_store.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/sessions/session.dart';

void main(List<String> args) async {
  // Create a cookie store with a secure cookie codec
  final store = CookieStore(
    codecs: [
      SecureCookie([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
    ],
    defaultOptions: Options(path: '/', maxAge: 3600),
  );

  final engine = Engine(middlewares: [
    sessionMiddleware(store, sessionName: 'routed_session'),
  ]);

  // Route to set session data
  engine.post('/session', (ctx) async {
    final session = ctx.get<Session>('session')!;
    final body = await ctx.request.body();
    final data = jsonDecode(body) as Map<String, dynamic>;
    session.values.addAll(data);
    ctx.json({'message': 'Session data set', 'data': session.values});
  });

  // Route to get session data
  engine.get('/session', (ctx) {
    final session = ctx.get<Session>('session')!;
    ctx.json({'session_data': session.values});
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
