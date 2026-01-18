import 'package:routed/routed.dart';

/// Demonstrates the `requireFound` and `fetchOr404` helpers for view logic.
Future<void> main() async {
  final engine = Engine();

  final users = {
    '1': {'id': '1', 'name': 'Ada Lovelace'},
    '2': {'id': '2', 'name': 'Alan Turing'},
  };

  engine.get('/users/{id}', (ctx) async {
    final id = ctx.mustGetParam<String>('id');

    final user = await ctx.fetchOr404(() async => users[id]);
    return ctx.json(user);
  });

  engine.get('/sessions/current', (ctx) async {
    final session = ctx.requireFound(
      ctx.headers.value('x-session-id'),
      message: 'Session missing',
    );
    return ctx.json({'sessionId': session});
  });

  await engine.initialize();
  await engine.serve(host: '127.0.0.1', port: 8083);
  print(
    'Try: curl -H "x-session-id: abc" http://127.0.0.1:8083/sessions/current',
  );
  print('Try: curl http://127.0.0.1:8083/users/1');
  print('Try: curl http://127.0.0.1:8083/users/999  # returns 404');
}
