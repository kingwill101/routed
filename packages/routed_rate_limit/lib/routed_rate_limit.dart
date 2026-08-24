/// Routed integration for framework-neutral request and authentication rate
/// limiting.
///
/// This package adapts [RateLimitService] to Routed's [EngineContext],
/// middleware chain, provider lifecycle, and `server_auth` authentication
/// flow. Configure policies with the `server_rate_limit` exports, then share
/// one service between the provider, request middleware, and authentication
/// options.
///
/// The following example assumes that `backend` is an already configured
/// [RateLimiterBackend], such as a cache-backed backend appropriate for the
/// deployment:
///
/// ```dart
/// final policies = compileRateLimitPolicies(
///   specs: [
///     const RateLimitPolicySpec(
///       name: 'public-api',
///       match: '/api/**',
///       method: 'GET',
///       strategy: RateLimitStrategy.slidingWindow,
///       capacity: 60,
///       interval: Duration.zero,
///       window: Duration(minutes: 1),
///       period: Duration.zero,
///       burstMultiplier: null,
///       key: RateLimitKeySpec.ip(),
///       failover: RateLimitFailoverMode.block,
///     ),
///   ],
///   backend: backend,
///   defaultFailover: RateLimitFailoverMode.block,
/// );
/// final service = RateLimitService(policies);
/// final engine = await Engine.create(
///   providers: [
///     ...Engine.defaultProviders,
///     RoutedRateLimitProvider(RateLimitConfig(service: service)),
///   ],
/// );
/// engine.addGlobalMiddleware(rateLimitMiddleware(service));
/// ```
///
/// IP-based policies use the request's trusted client address. Configure the
/// application's trusted proxy settings before relying on forwarded client
/// addresses. Header-based policies should use a header that clients cannot
/// forge, or be applied only after the application has authenticated and
/// normalized that identity.
library;

import 'package:routed_core/routed_core.dart';
import 'package:server_auth/server_auth.dart';
import 'package:server_rate_limit/server_rate_limit.dart';

export 'package:server_auth/server_auth.dart'
    show
        AuthRateLimitAction,
        AuthRateLimitDecision,
        AuthRateLimitException,
        AuthRateLimitOperation,
        AuthRateLimitRequest,
        AuthRateLimiter;
export 'package:server_rate_limit/server_rate_limit.dart';
export 'src/events/rate_limit_events.dart';

/// Adds rate-limit service accessors to a Routed request context.
extension RateLimitEngineContext on EngineContext {
  /// Returns the configured request rate-limit service.
  ///
  /// The typed registration is preferred. For compatibility with providers
  /// that register a dynamic service, a dynamic registration containing a
  /// [RateLimitService] is also accepted.
  ///
  /// Throws [StateError] when no compatible service has been registered in
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

  /// Whether a typed [RateLimitService] is registered in this request
  /// container.
  ///
  /// This getter intentionally does not inspect the dynamic compatibility
  /// registration used by [rateLimitService]. Call [rateLimitService] when a
  /// dynamically registered service must also be recognized.
  bool get hasRateLimitService => container.has<RateLimitService>();

  /// Evaluates [request] using this context's configured rate-limit service.
  ///
  /// Returns `null` when no policy matches, no policy can resolve an identity,
  /// or every matching policy allows the request. A blocked evaluation returns
  /// the first blocking [RateLimitOutcome] in policy order.
  ///
  /// Throws [StateError] when the request container has no rate-limit service.
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
///
/// The adapter does not register or dispose [service]. The provider or other
/// application lifecycle component that owns the service remains responsible
/// for its lifetime.
final class RoutedAuthRateLimiter implements AuthRateLimiter<EngineContext> {
  /// Creates an auth adapter backed by [service].
  const RoutedAuthRateLimiter(this.service);

  /// The request rate-limit service used for auth operations.
  ///
  /// The same service may also be passed to [rateLimitMiddleware] so browser
  /// requests and authentication operations consume the intended shared
  /// policies and backend state.
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
///
/// Instances are created by [RoutedAuthRateLimiter] for the duration of an
/// authentication check. The [identifier] is intended for a non-secret
/// account or provider key; callers should not put credentials or one-time
/// tokens in it.
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

  /// HTTP method copied from the underlying Routed request.
  @override
  String get method => _context.request.method;

  /// Path copied from the underlying Routed request, without its query.
  @override
  String get path => _context.request.uri.path;

  /// Trusted client address resolved by the underlying Routed request.
  @override
  String get clientIP => _context.request.clientIP;

  /// Remote address of the directly connected peer.
  @override
  String get remoteAddr => _context.request.remoteAddr;

  /// Returns the named request header, or the underlying request's empty
  /// value when it is absent.
  @override
  String header(String name) => _context.request.header(name);
}

/// Creates middleware that applies [service] before invoking the next handler.
///
/// When a policy blocks, the middleware stops the chain and returns status
/// `429` with a `Retry-After` response header. The retry duration is expressed
/// in whole seconds and is clamped to at least one second. When no policy
/// blocks, the middleware invokes `next` and returns its response.
///
/// If the context does not already contain a typed [RateLimitService], the
/// middleware registers [service] in the request container. It does not replace
/// an existing typed registration, but it always evaluates this request with
/// the [service] passed to the function. Pass the same instance to
/// [RoutedRateLimitProvider] when the context accessor and middleware should
/// observe identical state.
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
///
/// The configuration holds a ready-to-use [RateLimitService] rather than a
/// second policy representation. Build policies with the `server_rate_limit`
/// compiler before constructing this object.
class RateLimitConfig implements ValidatableConfiguration {
  /// Creates typed configuration for Routed rate limiting.
  ///
  /// An omitted [service] creates an empty service, leaving rate limiting
  /// disabled until policies are supplied. An empty service is safe to
  /// register, but [rateLimitMiddleware] will not consume any quota until a
  /// policy is present.
  RateLimitConfig({RateLimitService? service})
    : service = service ?? RateLimitService(const []);

  /// Service used by the provider and request middleware.
  ///
  /// The provider disposes this service during cleanup, including the
  /// backends owned by its policies. Do not share it with another owner unless
  /// their lifecycles are coordinated.
  final RateLimitService service;

  /// Validates this configuration.
  ///
  /// Policy validation and backend construction happen before the service is
  /// passed to this configuration, so this adapter has no additional checks.
  @override
  void validate(ConfigValidationContext context) {}
}

/// Registers the configured rate-limit service with a Routed application.
///
/// [register] exposes the service as both its typed registration and the
/// dynamic compatibility registration used by older provider compositions.
/// [cleanup] disposes the configured service; the provider therefore owns the
/// service for the lifetime of the application that registered it.
class RoutedRateLimitProvider extends ServiceProvider
    with ProvidesTypedConfiguration<RateLimitConfig> {
  /// Creates a provider for [configuration].
  ///
  /// An omitted configuration creates an empty service, so rate limiting is
  /// disabled until a configured service is supplied.
  RoutedRateLimitProvider([RateLimitConfig? configuration])
    : configuration = configuration ?? RateLimitConfig();

  /// Typed rate-limit configuration used by this provider.
  @override
  final RateLimitConfig configuration;

  /// Registers the configured service in [container].
  @override
  void register(Container container) {
    container
      ..singleton<RateLimitService>((_) async => configuration.service)
      ..instance<dynamic>(configuration.service);
  }

  /// Completes provider startup.
  ///
  /// No startup work is required because the service is fully constructed by
  /// [RateLimitConfig].
  @override
  Future<void> boot(Container container) async {}

  /// Disposes the configured service and its policy backends.
  @override
  Future<void> cleanup(Container container) => configuration.service.dispose();
}

/// Registers the rate-limit provider factory in the shared registry.
///
/// The factory is stored under `routed.rate_limit`, allowing applications that
/// use the shared provider registry to create [RoutedRateLimitProvider]
/// instances without importing the concrete provider at every composition
/// site. Direct provider construction remains available for explicit engine
/// composition.
void registerRoutedRateLimitProviders() {
  ProviderRegistry.instance.register(
    'routed.rate_limit',
    factory: RoutedRateLimitProvider.new,
    description: 'Rate-limit service and context helpers.',
  );
}
