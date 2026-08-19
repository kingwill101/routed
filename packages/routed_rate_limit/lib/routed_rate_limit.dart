library;

import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart';
import 'package:server_rate_limit/server_rate_limit.dart';

export 'package:server_rate_limit/server_rate_limit.dart';
export 'package:server_auth/server_auth.dart'
    show
        AuthRateLimitAction,
        AuthRateLimitDecision,
        AuthRateLimitException,
        AuthRateLimitOperation,
        AuthRateLimitRequest,
        AuthRateLimiter;
export 'src/events/rate_limit_events.dart';

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

/// Adapts the existing request rate-limit service to [AuthRateLimiter].
///
/// Policies are evaluated against the actual Routed request, so configured
/// method/path matchers and key resolvers remain the single source of truth.
/// The adapter does not copy passwords, OAuth codes, or verification tokens
/// into a rate-limit request. IP-based policies use Routed's trusted-proxy
/// resolution through [EngineContext.request.clientIP].
final class RoutedAuthRateLimiter implements AuthRateLimiter<EngineContext> {
  const RoutedAuthRateLimiter(this.service);

  final RateLimitService service;

  @override
  Future<AuthRateLimitDecision> check(
    AuthRateLimitRequest<EngineContext> request,
  ) async {
    final outcome = await service.check(
      _ContextRateLimitRequest(request.context),
    );
    if (outcome == null || outcome.allowed) {
      return const AuthRateLimitDecision.allow();
    }
    return AuthRateLimitDecision.block(retryAfter: outcome.retryAfter);
  }
}

Middleware rateLimitMiddleware(RateLimitService service) {
  return (ctx, next) async {
    if (!ctx.container.has<RateLimitService>()) {
      ctx.container.instance<RateLimitService>(service);
    }

    final outcome = await service.check(_ContextRateLimitRequest(ctx));
    if (outcome != null && !outcome.allowed) {
      ctx.response.headers.set(
        HttpHeaders.retryAfterHeader,
        outcome.retryAfter.inSeconds.clamp(1, 2147483647).toString(),
      );
      ctx.abortWithStatus(HttpStatus.tooManyRequests, 'Too Many Requests');
      return ctx.response;
    }

    return next();
  };
}

final class _ContextRateLimitRequest implements RateLimitRequest {
  _ContextRateLimitRequest(this.context);

  final EngineContext context;

  @override
  String get method => context.request.method;

  @override
  String get path => context.request.uri.path;

  @override
  String get clientIP => context.request.clientIP;

  @override
  String get remoteAddr => context.request.remoteAddr;

  @override
  String header(String name) => context.request.header(name);
}

/// Typed configuration for the rate-limit integration.
class RateLimitConfig implements ValidatableConfiguration {
  RateLimitConfig({RateLimitService? service})
    : service = service ?? RateLimitService(const []);

  final RateLimitService service;

  @override
  void validate(ConfigValidationContext context) {}
}

class RoutedRateLimitProvider extends ServiceProvider
    with ProvidesTypedConfiguration<RateLimitConfig> {
  /// Defaults to an empty policy list (rate limiting disabled until configured).
  RoutedRateLimitProvider([RateLimitConfig? configuration])
    : configuration = configuration ?? RateLimitConfig();

  @override
  final RateLimitConfig configuration;

  @override
  void register(Container container) {
    container.singleton<RateLimitService>((_) async => configuration.service);
    container.instance<dynamic>(configuration.service);
  }

  @override
  Future<void> boot(Container container) async {}

  @override
  Future<void> cleanup(Container container) => configuration.service.dispose();
}

/// Registers the rate-limit provider factory in the shared registry.
void registerRoutedRateLimitProviders() {
  ProviderRegistry.instance.register(
    'routed.rate_limit',
    factory: RoutedRateLimitProvider.new,
    description: 'Rate-limit service and context helpers.',
  );
}
