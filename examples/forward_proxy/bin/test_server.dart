import 'package:routed/routed.dart';

void main() async {
  final engine = Engine(
    middlewares: [
      (EngineContext ctx, Next next) async {
        print('[Test Server] Received request: ${ctx.method} ${ctx.path}');
        return await next();
      },
    ],
  );

  // Test endpoints
  engine.get('/hello', (ctx) {
    return ctx.json({
      'message': 'Hello from test server!',
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  engine.get('/headers', (ctx) {
    final headers = <String, String>{};
    ctx.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return ctx.json({'headers': headers, 'client_ip': ctx.clientIP});
  });

  engine.post('/echo', (ctx) async {
    final body = await ctx.body();
    return ctx.json({'method': ctx.method, 'path': ctx.path, 'body': body});
  });

  // Start the test server
  await engine.serve(port: 3001);
  print('Test server running at http://localhost:3001');
}
