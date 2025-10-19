import 'package:routed/routed.dart';
import 'package:routed/src/middleware/timeout.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router();

  // Add timeout middleware to specific routes
  router.get('/fast', (ctx) {
    ctx.string('Fast response');
  }, middlewares: [timeoutMiddleware(Duration(seconds: 1))]);

  router.get('/slow', (ctx) async {
    await Future.delayed(Duration(seconds: 2));
    ctx.string('Slow response');
  }, middlewares: [timeoutMiddleware(Duration(seconds: 1))]);

  // Add timeout middleware to a group of routes
  router.group(
    path: '/api',
    middlewares: [timeoutMiddleware(Duration(seconds: 3))],
    builder: (group) {
      group.get('/data', (ctx) async {
        await Future.delayed(Duration(seconds: 2));
        ctx.json({'message': 'Data retrieved'});
      });

      group.get('/timeout', (ctx) async {
        await Future.delayed(Duration(seconds: 4));
        ctx.json({'message': 'Should timeout before this'});
      });
    },
  );

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
