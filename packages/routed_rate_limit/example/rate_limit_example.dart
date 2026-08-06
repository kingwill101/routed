import 'package:routed/routed.dart';
import 'package:routed_rate_limit/routed_rate_limit.dart';

class _Req implements RateLimitRequest {
  _Req(this.method, this.path);
  @override final String method;
  @override final String path;
  @override String get clientIP => '127.0.0.1';
  @override String get remoteAddr => '127.0.0.1';
  @override String header(String name) => '';
}

void main() async {
  final service = RateLimitService([]);
  final engine = Engine();
  engine.get('/limited', (ctx) async {
    final outcome = await ctx.checkRateLimit(_Req('GET', '/limited'));
    return ctx.json({'allowed': outcome?.allowed ?? true});
  }, middlewares: [rateLimitMiddleware(service)]);
  print('routed_rate_limit example');
  await engine.close();
}
