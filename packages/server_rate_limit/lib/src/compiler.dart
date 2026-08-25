import 'dart:math';

import 'package:server_rate_limit/src/backend.dart';
import 'package:server_rate_limit/src/policy.dart';
import 'package:server_rate_limit/src/service.dart' show RateLimitService;

/// Key resolver strategies supported by [RateLimitPolicySpec].
enum RateLimitKeyKind {
  /// Uses the request client IP, falling back to the remote address.
  ip,

  /// Uses a named request header.
  header,
}

/// Declarative key resolver configuration used by [compileRateLimitPolicies].
///
/// Use [RateLimitKeySpec.ip] for a network identity or
/// [RateLimitKeySpec.header] for an application-supplied identity such as a
/// tenant ID. If a header specification is blank, compilation falls back to
/// IP resolution.
class RateLimitKeySpec {
  /// Creates a resolver specification based on the request IP.
  const RateLimitKeySpec.ip() : kind = RateLimitKeyKind.ip, header = null;

  /// Creates a resolver specification based on [header].
  ///
  /// A blank or whitespace-only header name is treated as an IP resolver when
  /// the specification is compiled.
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
  ///
  /// This is the refill capacity for [RateLimitStrategy.tokenBucket] and the
  /// request limit for the window and quota strategies. The compiler clamps it
  /// to at least one.
  final int capacity;

  /// Refill interval used by [RateLimitStrategy.tokenBucket].
  ///
  /// Other strategies ignore this value. Non-positive values are normalized to
  /// one second during compilation.
  final Duration interval;

  /// Window length used by [RateLimitStrategy.slidingWindow].
  ///
  /// Other strategies ignore this value. The runtime treats a non-positive
  /// duration as a one-millisecond window.
  final Duration window;

  /// Quota period used by [RateLimitStrategy.quota].
  ///
  /// Other strategies ignore this value. The runtime treats a non-positive
  /// duration as a one-millisecond period.
  final Duration period;

  /// Optional token-bucket burst multiplier.
  ///
  /// Other strategies ignore this value. Non-positive values use `1.0` during
  /// compilation.
  final double? burstMultiplier;

  /// Strategy used to resolve the request identity.
  ///
  /// If the resolver cannot produce an identity, the service skips this
  /// policy for the request.
  final RateLimitKeySpec key;

  /// Failover behavior for this policy, or the compiler default when omitted.
  final RateLimitFailoverMode? failover;
}

/// Compiles one [RateLimitPolicySpec] into a runtime policy.
///
/// The returned policy uses [backend] for all state changes. Its failover mode
/// is the value from `spec.failover` when provided, otherwise
/// [defaultFailover].
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
///
/// The iterable is consumed once, and the returned list preserves its order.
/// [RateLimitService] uses that order when it evaluates policies.
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
///
/// A blank header name produces an [IpKeyResolver] so configuration loaded from
/// optional fields still has a deterministic identity strategy.
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
