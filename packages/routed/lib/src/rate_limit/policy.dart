import 'dart:math';

import 'package:routed/src/request.dart';

import 'backend.dart';

/// Available enforcement strategies for rate limiting.
enum RateLimitStrategy { tokenBucket, slidingWindow, quota }

/// Behaviour when the distributed backend becomes unavailable.
enum RateLimitFailoverMode { allow, block, local }

/// Base contract for algorithm-specific configuration.
abstract class RateLimitAlgorithmConfig {
  const RateLimitAlgorithmConfig(this.strategy);

  final RateLimitStrategy strategy;
}

/// Token bucket configuration parameters shared by all backends.
class TokenBucketConfig extends RateLimitAlgorithmConfig {
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

  /// Upper bound of tokens after refills (capacity * burst).
  final double maxTokens;

  /// Tokens added per millisecond, derived from [refillTokens] and [refillInterval].
  double get refillPerMillisecond => refillInterval.inMilliseconds == 0
      ? double.infinity
      : refillTokens / refillInterval.inMilliseconds;
}

/// Sliding-window configuration maintaining a strict window boundary.
class SlidingWindowConfig extends RateLimitAlgorithmConfig {
  SlidingWindowConfig({required this.limit, required this.window})
    : super(RateLimitStrategy.slidingWindow);

  /// Maximum number of requests permitted within the window.
  final int limit;

  /// Window length.
  final Duration window;
}

/// Rolling quota configuration for long-lived limits.
class QuotaConfig extends RateLimitAlgorithmConfig {
  QuotaConfig({required this.limit, required this.period})
    : super(RateLimitStrategy.quota);

  /// Maximum number of requests permitted within the quota period.
  final int limit;

  /// Duration of the quota period (e.g., daily, monthly).
  final Duration period;
}

/// Result of a rate-limit evaluation.
class RateLimitOutcome {
  RateLimitOutcome.allowed({
    required this.remaining,
    this.retryAfter = Duration.zero,
    this.failoverMode,
  }) : allowed = true;

  RateLimitOutcome.blocked({
    required this.retryAfter,
    required this.remaining,
    this.failoverMode,
  }) : allowed = false;

  final bool allowed;
  final Duration retryAfter;
  final int remaining;
  final RateLimitFailoverMode? failoverMode;
}

typedef _MatchFn = bool Function(Request request);

class RequestMatcher {
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
      return (_) => true;
    }

    final regex = RegExp(_wildcardToRegex(trimmed));
    return (Request request) {
      if (method != null && method.isNotEmpty) {
        if (request.method.toUpperCase() != method.toUpperCase()) {
          return false;
        }
      }
      return regex.hasMatch(request.path);
    };
  }

  static String _wildcardToRegex(String pattern) {
    final escaped = pattern.splitMapJoin(
      RegExp(r'(\*\*|\*)'),
      onNonMatch: (match) => RegExp.escape(match),
      onMatch: (match) {
        if (match[0] == '**') {
          return '.*';
        }
        return '[^/]*';
      },
    );
    return '^$escaped\$';
  }

  bool matches(Request request) => _matchFn(request);

  @override
  String toString() => '${_method ?? '*'} $_pattern';
}

/// Resolves the identity string used for rate-limiting.
abstract class RateLimitKeyResolver {
  const RateLimitKeyResolver();

  String? resolve(Request request);
}

class IpKeyResolver extends RateLimitKeyResolver {
  const IpKeyResolver();

  @override
  String? resolve(Request request) {
    final ip = request.clientIP;
    if (ip.isNotEmpty) return ip;
    return request.remoteAddr.isNotEmpty ? request.remoteAddr : null;
  }
}

class HeaderKeyResolver extends RateLimitKeyResolver {
  const HeaderKeyResolver(this.header);

  final String header;

  @override
  String? resolve(Request request) {
    final value = request.header(header);
    if (value.isNotEmpty) return value;
    return null;
  }
}

typedef CustomKeyResolver = String? Function(Request request);

class CustomResolver extends RateLimitKeyResolver {
  const CustomResolver(this._resolver);

  final CustomKeyResolver _resolver;

  @override
  String? resolve(Request request) => _resolver(request);
}

/// Compiled policy ready for runtime enforcement.
class CompiledRateLimitPolicy {
  CompiledRateLimitPolicy({
    required this.name,
    required this.matcher,
    required this.keyResolver,
    required this.algorithm,
    required this.backend,
    required this.failover,
  });

  final String name;
  final RequestMatcher matcher;
  final RateLimitKeyResolver keyResolver;
  final RateLimitAlgorithmConfig algorithm;
  final RateLimiterBackend backend;
  final RateLimitFailoverMode failover;

  bool matches(Request request) => matcher.matches(request);

  Future<RateLimitOutcome> evaluate(String identity, DateTime now) {
    final bucketKey = '$name:$identity';
    return backend.consume(bucketKey, algorithm, now, failover: failover);
  }
}

/// Helper to build token bucket configuration from user parameters.
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
