import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  // Register routes directly on the Engine
  engine.get('/hello', (ctx) => ctx.string('Hello, World!'));

  engine.post('/echo', (ctx) async {
    final body = await ctx.request.body();
    ctx.string('Echo: $body');
  });

  // Apply middleware directly to the Engine
  engine.middlewares.add((ctx) async {
    ctx.setHeader('X-Engine-Middleware', 'Active');
    await ctx.next();
  });

  engine.get('/middleware', (ctx) => ctx.string('Middleware Test'));

  // Route builder with name and groups
  engine.get('/users', (ctx) => ctx.string('User List')).name('users.list');

  engine.group(
    path: '/users',
    builder: (router) {
      router.get('/{userId:int}', (ctx) {
        final userId = ctx.param('userId');
        ctx.string('User Details for $userId');
      }).name('users.details');

      router.put('/{userId:int}', (ctx) {
        final userId = ctx.param('userId');
        ctx.string('Update User $userId');
      }).name('users.update');
    },
  );

  await engine.serve(host: '127.0.0.1', port: 8080);
}
