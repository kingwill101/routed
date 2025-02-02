import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router();

  // Basic GET route
  router.get('/hello', (ctx) {
    ctx.string('Hello, World!');
  });

  // Route with path parameters
  router.get('/users/{id}', (ctx) {
    final id = ctx.param('id');
    ctx.json({'message': 'Got user', 'id': id});
  });

  // POST route with JSON body
  router.post('/users', (ctx) async {
    final body = await ctx.request.body();
    ctx.json({
      'message': 'Created user',
      'data': body,
    });
  });

  // Route with query parameters
  router.get('/search', (ctx) {
    final query = ctx.query('q');
    final page = ctx.defaultQuery('page', '1');
    ctx.json({
      'query': query,
      'page': page,
    });
  });

  // Route group example
  router.group(
    path: '/api',
    builder: (group) {
      group.get('/status', (ctx) {
        ctx.json({'status': 'ok'});
      });

      group.post('/data', (ctx) async {
        final body = await ctx.request.body();
        ctx.json({'received': body});
      });
    },
  );

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
