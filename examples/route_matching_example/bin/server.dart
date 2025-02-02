import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router();

  // Define routes for all HTTP methods
  final methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'HEAD',
    'OPTIONS',
    'DELETE',
  ];

  for (final method in methods) {
    router.handle(method, '/test', (ctx) => ctx.string('$method ok'));
  }

  // Route with path parameters
  router.get('/test/{name}/{last_name}/{*wild}', (ctx) {
    final params = ctx.params;
    ctx.json({
      'name': params['name'],
      'last_name': params['last_name'],
      'wild': params['wild']
    });
  });

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
