/// Routed adapters for request and authentication rate limiting.
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

/// Adds rate-limit service accessors to a Routed request context.
extension RateLimitEngineContext on EngineContext {
  /// Returns the configured request rate-limit service.
  ///
  /// Throws [StateError] when no [RateLimitService] has been registered in
  /// the request container.
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

  /// Whether a [RateLimitService] is registered in this request container.
  bool get hasRateLimitService => container.has<RateLimitService>();

  /// Evaluates [request] using this context's configured rate-limit service.
  Future<RateLimitOutcome?> checkRateLimit(RateLimitRequest request) =>
      rateLimitService.check(request);
}

/// Adapts the existing request rate-limit service to [AuthRateLimiter].
///
/// Policies are evaluated against the actual Routed request, so configured
/// method/path matchers and key resolvers remain the single source of truth.
/// The adapter does not copy passwords, OAuth codes, or verification tokens
/// into a rate-limit request. IP-based policies use Routed's trusted-proxy
/// resolution through `clientIP`.
final class RoutedAuthRateLimiter implements AuthRateLimiter<EngineContext> {
  /// Creates an auth adapter backed by [service].
  const RoutedAuthRateLimiter(this.service);

  /// The request rate-limit service used for auth operations.
  final RateLimitService service;

  @override
  Future<AuthRateLimitDecision> check(
    AuthRateLimitRequest<EngineContext> request,
  ) async {
    final outcome = await service.check(RoutedAuthRateLimitRequest._(request));
    if (outcome == null || outcome.allowed) {
      return const AuthRateLimitDecision.allow();
    }
    return AuthRateLimitDecision.block(retryAfter: outcome.retryAfter);
  }
}

/// Rate-limit request carrying the non-secret auth metadata supplied by
/// `server_auth`.
///
/// A [CustomResolver] can inspect this type to combine [operation],
/// [providerId], and [identifier] with request-derived properties such as the
/// trusted client address. No password, OTP, captcha token, bearer token, or
/// other endpoint payload is retained here.
final class RoutedAuthRateLimitRequest implements RateLimitRequest {
  /// Creates a request adapter from a `server_auth` auth request.
  RoutedAuthRateLimitRequest._(AuthRateLimitRequest<EngineContext> request)
    : operation = request.operation,
      providerId = request.providerId,
      identifier = request.identifier,
      _context = request.context;

  /// Auth operation being evaluated.
  final AuthRateLimitOperation operation;

  /// Auth provider identifier associated with the operation.
  final String providerId;

  /// Non-secret identifier supplied by the auth operation, when present.
  final String? identifier;
  final EngineContext _context;

  @override
  String get method => _context.request.method;

  @override
  String get path => _context.request.uri.path;

  @override
  String get clientIP => _context.request.clientIP;

  @override
  String get remoteAddr => _context.request.remoteAddr;

  @override
  String header(String name) => _context.request.header(name);
}

/// Creates middleware that applies [service] before invoking the next handler.
///
/// Blocked requests receive status `429` and a `Retry-After` response header.
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
  /// Creates typed configuration for Routed rate limiting.
  ///
  /// An omitted [service] creates an empty service, leaving rate limiting
  /// disabled until policies are supplied.
  RateLimitConfig({RateLimitService? service})
    : service = service ?? RateLimitService(const []);

  /// Service used by the provider and request middleware.
  final RateLimitService service;

  @override
  void validate(ConfigValidationContext context) {}
}

/// Registers the configured rate-limit service with a Routed application.
class RoutedRateLimitProvider extends ServiceProvider
    with ProvidesTypedConfiguration<RateLimitConfig> {
  /// Defaults to an empty policy list (rate limiting disabled until configured).
  RoutedRateLimitProvider([RateLimitConfig? configuration])
    : configuration = configuration ?? RateLimitConfig();

  /// Typed rate-limit configuration used by this provider.
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
