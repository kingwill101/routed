import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();
  final startTime = DateTime.now();

  // Track proxy statistics
  var requestCount = 0;
  var errorCount = 0;

  // Proxy status endpoint
  engine.get('/status', (ctx) {
    return ctx.json({
      'total_requests': requestCount,
      'error_count': errorCount,
      'uptime': DateTime.now().difference(startTime).toString(),
    });
  });

  // Forward proxy handler
  engine.get('/{*path}', (ctx) async {
    requestCount++;
    final path = ctx.request.path;
    print('[Proxy Server] Forwarding request: ${ctx.request.method} $path');

    try {
      // Target URL (test server)
      final targetUrl = 'http://localhost:3001$path';

      // Forward the request
      await ctx.forward(
        targetUrl,
        options: ProxyOptions(
          forwardHeaders: true,
          headers: {'X-Custom-Proxy': 'Example'},
          addProxyHeaders: true,
        ),
      );
    } catch (e) {
      errorCount++;
      return ctx.json({
        'error': 'Proxy error: ${e.toString()}',
        'target_path': ctx.request.path,
      }, statusCode: 502);
    }
  });

  // Start the proxy server
  await engine.serve(port: 3000);
  print('Proxy server running at http://localhost:3000');
}
