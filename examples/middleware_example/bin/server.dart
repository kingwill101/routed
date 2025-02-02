import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();

  // Engine-level middleware
  engine.middlewares.add((ctx) async {
    print('Engine middleware: Before request');
    ctx.setHeader('X-Engine-Middleware', 'Active');
    await ctx.next();
    print('Engine middleware: After request');
  });

  final router = Router(middlewares: [
    (ctx) async {
      print('Router middleware: Before request');
      ctx.setHeader('X-Router-Middleware', 'Active');
      await ctx.next();
      print('Router middleware: After request');
    }
  ]);

  // Route with route-level middleware
  router.get(
    '/test',
    (ctx) => ctx.string('Hello from route!'),
    middlewares: [
      (ctx) async {
        print('Route middleware: Before request');
        ctx.setHeader('X-Route-Middleware', 'Active');
        await ctx.next();
        print('Route middleware: After request');
      },
    ],
  );

  // Route group with group-level middleware
  router.group(
    path: '/admin',
    middlewares: [
      (ctx) async {
        print('Group middleware: Before request');
        ctx.setHeader('X-Group-Middleware', 'Active');
        await ctx.next();
        print('Group middleware: After request');
      },
    ],
    builder: (group) {
      group.get('/dashboard', (ctx) => ctx.string('Admin Dashboard'));
    },
  );

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
