library;

import 'package:routed/routed.dart';
import 'package:server_rate_limit/server_rate_limit.dart';

export 'package:server_rate_limit/server_rate_limit.dart';

extension RateLimitEngineContext on EngineContext {
  RateLimitService get rateLimitService {
    if (container.has<RateLimitService>()) {
      return container.get<RateLimitService>();
    }
    if (container.has<dynamic>()) {
      final dynamic m = container.get<dynamic>();
      if (m is RateLimitService) return m;
    }
    throw StateError('Rate limit service not configured');
  }

  bool get hasRateLimitService => container.has<RateLimitService>();
  Future<RateLimitOutcome?> checkRateLimit(RateLimitRequest request) =>
      rateLimitService.check(request);
}

Middleware rateLimitMiddleware(RateLimitService service) {
  return (ctx, next) {
    if (!ctx.container.has<RateLimitService>()) {
      ctx.container.instance<RateLimitService>(service);
    }
    return next();
  };
}

class RoutedRateLimitProvider extends ServiceProvider {
  RoutedRateLimitProvider(this.service);
  final RateLimitService service;
  @override
  void register(Container container) {
    container.singleton<RateLimitService>((_) async => service);
    container.instance<dynamic>(service);
  }

  @override
  Future<void> boot(Container container) async {}
}
