import 'package:routed/routed.dart';
import 'package:http/http.dart' as http;

void main(List<String> args) async {
  final engine = Engine();
  final client = http.Client();

  // Middleware to log proxy requests
  engine.middlewares.add((ctx) async {
    print('Proxying request to: ${ctx.request.path}');
    await ctx.next();
  });

  // Forward all requests to example.com
  engine.handle('*', '/{*path}', (ctx) async {
    final path = ctx.param('path') ?? '';
    final targetUrl = 'https://example.com/$path';

    try {
      final proxyRequest = http.Request(
        ctx.request.method,
        Uri.parse(targetUrl),
      );
      // Copy headers from original request
      ctx.request.headers.forEach((key, values) {
        proxyRequest.headers[key] = values.join(',');
      });

      // Forward the request body for POST/PUT methods
      if (['POST', 'PUT'].contains(ctx.request.method)) {
        proxyRequest.body = await ctx.request.body();
      }

      final streamedResponse = await client.send(proxyRequest);
      final response = await http.Response.fromStream(streamedResponse);

      // Copy response headers and status
      for (var header in response.headers.entries) {
        ctx.setHeader(header.key, header.value);
      }
      ctx.status(response.statusCode);

      // Send response body
      ctx.string(response.body);
    } catch (e) {
      ctx.status(500);
      ctx.json({
        'error': 'Proxy Error',
        'message': e.toString(),
      });
    }
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
