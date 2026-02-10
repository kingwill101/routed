import 'package:routed/src/context/context.dart';
import 'package:routed/src/router/types.dart' show Middleware, Next;
import '../rate_limit/service.dart';

Middleware rateLimitMiddleware(RateLimitService service) {
  return (EngineContext ctx, Next next) async {
    if (!service.enabled) {
      return await next();
    }

    final outcome = await service.check(ctx.request);
    if (outcome == null || outcome.allowed) {
      return await next();
    }

    final retryDuration = outcome.retryAfter;
    final retrySeconds = retryDuration.inSeconds <= 0
        ? (retryDuration.inMilliseconds > 0 ? 1 : 0)
        : retryDuration.inSeconds;
    ctx.response.headers.set('Retry-After', retrySeconds.toString());
    ctx.errorResponse(
      statusCode: 429,
      message: 'Too Many Requests',
      jsonBody: {'error': 'too_many_requests', 'retry_after': retrySeconds},
    );
    ctx.abort();
    return ctx.response;
  };
}
