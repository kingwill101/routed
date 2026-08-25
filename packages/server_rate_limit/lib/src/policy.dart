import 'dart:math';

import 'package:server_rate_limit/src/backend.dart';

/// Available enforcement strategies for rate limiting.
enum RateLimitStrategy {
  /// Refills a token balance over time.
  tokenBucket,

  /// Counts requests within aligned time windows.
  slidingWindow,

  /// Counts requests within a longer-lived quota period.
  quota,
}

/// Behavior when the distributed backend becomes unavailable.
enum RateLimitFailoverMode {
  /// Allows the request to proceed without enforcing the distributed limit.
  allow,

  /// Rejects the request while the backend is unavailable.
  block,

  /// Enforces the limit against process-local fallback state.
  local,
}

/// Base configuration contract for a rate-limit algorithm.
abstract class RateLimitAlgorithmConfig {
  /// Creates configuration for [strategy].
  const RateLimitAlgorithmConfig(this.strategy);

  /// Algorithm represented by this configuration.
  final RateLimitStrategy strategy;
}

/// Token-bucket parameters shared by all backends.
///
/// [capacity] describes the refill amount used by the compiler-created
/// configuration. [maxTokens] controls the burst allowance and may be greater
/// than [capacity]. Directly constructed configurations are not normalized;
/// use [buildBucketConfig] when accepting untrusted or user-entered values.
class TokenBucketConfig extends RateLimitAlgorithmConfig {
  /// Creates a token-bucket configuration.
  TokenBucketConfig({
    required this.capacity,
    required this.refillTokens,
    required this.refillInterval,
    required this.maxTokens,
  }) : super(RateLimitStrategy.tokenBucket);

  /// Maximum number of requests allowed before throttling begins.
  final int capacity;

  /// Number of tokens added every [refillInterval].
  final double refillTokens;

  /// How frequently tokens are refilled.
  final Duration refillInterval;

  /// Upper bound of tokens after refills, usually [capacity] multiplied by a
  /// burst factor.
  final double maxTokens;

  /// Number of tokens added per millisecond.
  double get refillPerMillisecond => refillInterval.inMilliseconds == 0
      ? double.infinity
      : refillTokens / refillInterval.inMilliseconds;
}

/// Sliding-window configuration that maintains a strict window boundary.
///
/// Requests are counted in aligned windows rather than in a rolling list of
/// timestamps. The backend calculates the retry delay from the end of the
/// current window.
class SlidingWindowConfig extends RateLimitAlgorithmConfig {
  /// Creates a sliding-window configuration.
  SlidingWindowConfig({required this.limit, required this.window})
    : super(RateLimitStrategy.slidingWindow);

  /// Maximum number of requests permitted within the window.
  final int limit;

  /// Window length.
  final Duration window;
}

/// Rolling quota configuration for a longer-lived limit.
///
/// The quota resets at an aligned period boundary. It is useful for daily or
/// monthly-style counters, but it is not a calendar-aware billing quota.
class QuotaConfig extends RateLimitAlgorithmConfig {
  /// Creates a quota configuration.
  QuotaConfig({required this.limit, required this.period})
    : super(RateLimitStrategy.quota);

  /// Maximum number of requests permitted within the quota period.
  final int limit;

  /// Duration of the quota period (e.g., daily, monthly).
  final Duration period;
}

/// Result returned by a rate-limit evaluation.
///
/// A blocked result contains a suggested [retryAfter] duration. Treat that
/// duration as advisory: callers should still apply their own response and
/// retry policy.
class RateLimitOutcome {
  /// Creates an outcome that allows the request.
  RateLimitOutcome.allowed({
    required this.remaining,
    this.retryAfter = Duration.zero,
    this.failoverMode,
  }) : allowed = true;

  /// Creates an outcome that blocks the request.
  RateLimitOutcome.blocked({
    required this.retryAfter,
    required this.remaining,
    this.failoverMode,
  }) : allowed = false;

  /// Whether the request may proceed.
  final bool allowed;

  /// Suggested delay before retrying a blocked request.
  final Duration retryAfter;

  /// Number of requests or tokens remaining after the evaluation.
  final int remaining;

  /// Failover mode used to produce this outcome, when applicable.
  final RateLimitFailoverMode? failoverMode;
}

/// Request data required by the rate-limit policy runtime.
///
/// Adapt the host framework's request object to this small contract. The
/// runtime does not inspect framework-specific request types or mutate the
/// request.
abstract class RateLimitRequest {
  /// HTTP method for the request.
  String get method;

  /// Request path used for policy matching.
  String get path;

  /// Client IP address, when available.
  ///
  /// Return an empty string when the host cannot determine the client address.
  /// Do not trust forwarded values unless the host has validated its proxy
  /// configuration.
  String get clientIP;

  /// Remote address of the connected peer.
  ///
  /// This is the fallback used by [IpKeyResolver] when [clientIP] is empty.
  String get remoteAddr;

  /// Returns the request header named [name], or an empty string when absent.
  String header(String name);
}

typedef _MatchFn = bool Function(RateLimitRequest request);

/// Matches requests against an optional method and wildcard path pattern.
///
/// Matching is anchored to the complete path. `*` matches characters within a
/// single path segment, while `**` can span `/` characters. A `null` method
/// matches every method; method comparisons are case-insensitive. A blank
/// pattern is treated as a catch-all.
class RequestMatcher {
  /// Creates a matcher for [pattern] and an optional HTTP [method].
  RequestMatcher({required String? method, required String pattern})
    : _method = method?.toUpperCase(),
      _pattern = pattern,
      _matchFn = _compile(method, pattern);

  final String? _method;
  final String _pattern;
  final _MatchFn _matchFn;

  static _MatchFn _compile(String? method, String pattern) {
    final trimmed = pattern.trim();

    if (trimmed == '*' || trimmed.isEmpty) {
      // Catch-all still honours the configured HTTP method: a policy with
      // method: GET and pattern '*' must not consume quota for POST/PUT/etc.
      return (RateLimitRequest request) => _matchesMethod(method, request);
    }

    final regex = RegExp(_wildcardToRegex(trimmed));
    return (RateLimitRequest request) {
      if (!_matchesMethod(method, request)) {
        return false;
      }
      return regex.hasMatch(request.path);
    };
  }

  static bool _matchesMethod(String? method, RateLimitRequest request) {
    if (method == null || method.isEmpty) {
      return true;
    }
    return request.method.toUpperCase() == method.toUpperCase();
  }

  static String _wildcardToRegex(String pattern) {
    final escaped = pattern.splitMapJoin(
      RegExp(r'(\*\*|\*)'),
      onNonMatch: RegExp.escape,
      onMatch: (match) {
        if (match[0] == '**') {
          return '.*';
        }
        return '[^/]*';
      },
    );
    return '^$escaped\$';
  }

  /// Returns whether [request] satisfies this matcher.
  bool matches(RateLimitRequest request) => _matchFn(request);

  @override
  String toString() => '${_method ?? '*'} $_pattern';
}

/// Resolves the identity string used for rate limiting.
///
/// Returning `null` skips the associated policy for that request. Resolvers
/// should return a stable, bounded identity rather than an entire request or
/// an untrusted value that can create unbounded backend keys.
// This interface is intentionally one method: it is the extension point for
// custom identity strategies.
// ignore: one_member_abstracts
abstract class RateLimitKeyResolver {
  /// Creates a key resolver.
  const RateLimitKeyResolver();

  /// Returns the identity for [request], or `null` when it cannot be resolved.
  String? resolve(RateLimitRequest request);
}

/// Resolves rate-limit identities from the client IP.
class IpKeyResolver extends RateLimitKeyResolver {
  /// Creates an IP key resolver.
  const IpKeyResolver();

  @override
  String? resolve(RateLimitRequest request) {
    final ip = request.clientIP;
    if (ip.isNotEmpty) return ip;
    return request.remoteAddr.isNotEmpty ? request.remoteAddr : null;
  }
}

/// Resolves rate-limit identities from a request header.
///
/// The header value is used as-is when non-empty. Validate and normalize
/// tenant or account identifiers before using them as a distributed key.
class HeaderKeyResolver extends RateLimitKeyResolver {
  /// Creates a header resolver for [header].
  const HeaderKeyResolver(this.header);

  /// Header name read from each request.
  final String header;

  @override
  String? resolve(RateLimitRequest request) {
    final value = request.header(header);
    if (value.isNotEmpty) return value;
    return null;
  }
}

/// Callback signature for custom request identity resolution.
///
/// Return `null` when [request] should not consume this policy's quota.
typedef CustomKeyResolver = String? Function(RateLimitRequest request);

/// Resolves identities using a caller-provided callback.
class CustomResolver extends RateLimitKeyResolver {
  /// Creates a resolver backed by a caller-provided callback.
  const CustomResolver(this._resolver);

  final CustomKeyResolver _resolver;

  @override
  String? resolve(RateLimitRequest request) => _resolver(request);
}

/// Compiled policy ready for runtime enforcement.
///
/// A policy combines matching, identity resolution, algorithm state, backend
/// storage, and backend failure behavior into one evaluation unit.
class CompiledRateLimitPolicy {
  /// Creates a compiled policy from its matching, identity, and backend parts.
  CompiledRateLimitPolicy({
    required this.name,
    required this.matcher,
    required this.keyResolver,
    required this.algorithm,
    required this.backend,
    required this.failover,
  });

  /// Stable policy name used to namespace backend buckets.
  final String name;

  /// Request matcher used to select this policy.
  final RequestMatcher matcher;

  /// Identity resolver used to select a caller bucket.
  final RateLimitKeyResolver keyResolver;

  /// Algorithm configuration evaluated by this policy.
  final RateLimitAlgorithmConfig algorithm;

  /// Backend that stores and evaluates this policy's state.
  final RateLimiterBackend backend;

  /// Behavior used if [backend] cannot evaluate a request.
  final RateLimitFailoverMode failover;

  /// Returns whether [request] is selected by this policy.
  bool matches(RateLimitRequest request) => matcher.matches(request);

  /// Evaluates one request for [identity] at [now].
  ///
  /// The backend bucket key is formed by joining [name] and [identity] with a
  /// colon. Keep both values stable and appropriately bounded for the backing
  /// store.
  Future<RateLimitOutcome> evaluate(String identity, DateTime now) {
    final bucketKey = '$name:$identity';
    return backend.consume(bucketKey, algorithm, now, failover: failover);
  }
}

/// Builds a normalized token-bucket configuration from user parameters.
///
/// Values below one capacity are clamped to one. Non-positive refill
/// intervals use a one-second interval. A non-positive burst multiplier uses
/// the default multiplier of `1.0`. The resulting [TokenBucketConfig.maxTokens]
/// is `capacity * burstMultiplier`.
TokenBucketConfig buildBucketConfig({
  required int capacity,
  required Duration refillInterval,
  double? burstMultiplier,
}) {
  final validatedCapacity = max(1, capacity);
  final interval = refillInterval <= Duration.zero
      ? const Duration(seconds: 1)
      : refillInterval;
  final burst = burstMultiplier != null && burstMultiplier > 0
      ? burstMultiplier
      : 1.0;
  final maxTokens = validatedCapacity * burst;
  return TokenBucketConfig(
    capacity: validatedCapacity,
    refillTokens: validatedCapacity.toDouble(),
    refillInterval: interval,
    maxTokens: maxTokens,
  );
}
