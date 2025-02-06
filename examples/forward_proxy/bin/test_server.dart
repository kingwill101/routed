import 'package:routed/routed.dart';

void main() async {
  final engine = Engine(middlewares: [
    (ctx) async {
      print(
          '[Test Server] Received request: ${ctx.request.method} ${ctx.request.path}');
      await ctx.next();
    }
  ]);

  // Test endpoints
  engine.get('/hello', (ctx) {
    return ctx.json({
      'message': 'Hello from test server!',
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  engine.get('/headers', (ctx) {
    final headers = <String, String>{};
    ctx.request.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return ctx.json({
      'headers': headers,
      'client_ip': ctx.request.ip,
    });
  });

  engine.post('/echo', (ctx) async {
    final body = await ctx.request.body();
    return ctx.json({
      'method': ctx.request.method,
      'path': ctx.request.path,
      'body': body,
    });
  });

  // Start the test server
  await engine.serve(port: 3001);
  print('Test server running at http://localhost:3001');
}
