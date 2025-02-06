import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine(
      config: EngineConfig(
    redirectTrailingSlash: true,
    handleMethodNotAllowed: true,
    forwardedByClientIP: true,
    remoteIPHeaders: ['X-Real-IP', 'X-Forwarded-For'],
  ));

  final router = Router();

  // Routes to demonstrate trailing slash and method not allowed
  router.get('/users', (ctx) => ctx.string('users'));
  router.post('/users', (ctx) => ctx.string('created'));

  // Route to demonstrate IP forwarding
  router.get('/ip', (ctx) => ctx.string(ctx.request.ip));

  engine.use(router);

  await engine.serve(host: '127.0.0.1', port: 8080);
}
