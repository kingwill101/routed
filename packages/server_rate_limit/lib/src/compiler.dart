import 'dart:math';

import 'package:server_rate_limit/src/backend.dart';
import 'package:server_rate_limit/src/policy.dart';

/// Key resolver strategies supported by [RateLimitPolicySpec].
enum RateLimitKeyKind {
  /// Uses the request client IP, falling back to the remote address.
  ip,

  /// Uses a named request header.
  header,
}

/// Declarative key resolver configuration used by [compileRateLimitPolicies].
class RateLimitKeySpec {
  /// Creates a resolver specification based on the request IP.
  const RateLimitKeySpec.ip() : kind = RateLimitKeyKind.ip, header = null;

  /// Creates a resolver specification based on [header].
  const RateLimitKeySpec.header(this.header) : kind = RateLimitKeyKind.header;

  /// The resolver strategy selected by this specification.
  final RateLimitKeyKind kind;

  /// The header name when [kind] is [RateLimitKeyKind.header].
  final String? header;
}

/// Declarative policy configuration that can be compiled into a runtime policy.
class RateLimitPolicySpec {
  /// Creates a policy specification.
  ///
  /// [name] identifies the policy's bucket namespace. [match] is a path
  /// pattern, [method] optionally restricts the HTTP method, and [strategy]
  /// selects which algorithm uses [capacity] and its associated duration.
  const RateLimitPolicySpec({
    required this.name,
    required this.match,
    required this.method,
    required this.strategy,
    required this.capacity,
    required this.interval,
    required this.window,
    required this.period,
    required this.burstMultiplier,
    required this.key,
    this.failover,
  });

  /// Stable name used to namespace the policy's buckets.
  final String name;

  /// Path or wildcard pattern matched by the policy.
  final String match;

  /// Optional HTTP method restriction.
  final String? method;

  /// Algorithm used to enforce the policy.
  final RateLimitStrategy strategy;

  /// Capacity passed to the selected algorithm.
  final int capacity;

  /// Refill interval used by [RateLimitStrategy.tokenBucket].
  final Duration interval;

  /// Window length used by [RateLimitStrategy.slidingWindow].
  final Duration window;

  /// Quota period used by [RateLimitStrategy.quota].
  final Duration period;

  /// Optional token-bucket burst multiplier.
  final double? burstMultiplier;

  /// Strategy used to resolve the request identity.
  final RateLimitKeySpec key;

  /// Failover behavior for this policy, or the compiler default when omitted.
  final RateLimitFailoverMode? failover;
}

/// Compiles one [RateLimitPolicySpec] into a runtime policy.
CompiledRateLimitPolicy compileRateLimitPolicy({
  required RateLimitPolicySpec spec,
  required RateLimiterBackend backend,
  required RateLimitFailoverMode defaultFailover,
}) {
  final algorithm = _buildAlgorithm(spec);
  final matcher = RequestMatcher(method: spec.method, pattern: spec.match);
  final keyResolver = buildRateLimitKeyResolver(spec.key);

  return CompiledRateLimitPolicy(
    name: spec.name,
    matcher: matcher,
    keyResolver: keyResolver,
    algorithm: algorithm,
    backend: backend,
    failover: spec.failover ?? defaultFailover,
  );
}

/// Compiles [specs] into immutable runtime policies.
List<CompiledRateLimitPolicy> compileRateLimitPolicies({
  required Iterable<RateLimitPolicySpec> specs,
  required RateLimiterBackend backend,
  required RateLimitFailoverMode defaultFailover,
}) {
  return specs
      .map(
        (spec) => compileRateLimitPolicy(
          spec: spec,
          backend: backend,
          defaultFailover: defaultFailover,
        ),
      )
      .toList(growable: false);
}

/// Builds a runtime key resolver from [spec].
RateLimitKeyResolver buildRateLimitKeyResolver(RateLimitKeySpec spec) {
  switch (spec.kind) {
    case RateLimitKeyKind.ip:
      return const IpKeyResolver();
    case RateLimitKeyKind.header:
      final header = spec.header?.trim();
      if (header == null || header.isEmpty) {
        return const IpKeyResolver();
      }
      return HeaderKeyResolver(header);
  }
}

RateLimitAlgorithmConfig _buildAlgorithm(RateLimitPolicySpec spec) {
  switch (spec.strategy) {
    case RateLimitStrategy.slidingWindow:
      return SlidingWindowConfig(
        limit: max(1, spec.capacity),
        window: spec.window,
      );
    case RateLimitStrategy.quota:
      return QuotaConfig(limit: max(1, spec.capacity), period: spec.period);
    case RateLimitStrategy.tokenBucket:
      return buildBucketConfig(
        capacity: spec.capacity,
        refillInterval: spec.interval,
        burstMultiplier: spec.burstMultiplier,
      );
  }
}
