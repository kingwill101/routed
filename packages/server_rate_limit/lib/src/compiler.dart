import 'dart:math';

import 'backend.dart';
import 'policy.dart';

/// Supported key resolver strategies for [RateLimitPolicySpec].
enum RateLimitKeyKind { ip, header }

/// Declarative key resolver spec used by [compileRateLimitPolicies].
class RateLimitKeySpec {
  const RateLimitKeySpec.ip() : kind = RateLimitKeyKind.ip, header = null;

  const RateLimitKeySpec.header(this.header)
    : kind = RateLimitKeyKind.header;

  final RateLimitKeyKind kind;
  final String? header;
}

/// Declarative policy spec that can be compiled into runtime policies.
class RateLimitPolicySpec {
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

  final String name;
  final String match;
  final String? method;
  final RateLimitStrategy strategy;
  final int capacity;
  final Duration interval;
  final Duration window;
  final Duration period;
  final double? burstMultiplier;
  final RateLimitKeySpec key;
  final RateLimitFailoverMode? failover;
}

/// Compiles a single [RateLimitPolicySpec] into a runtime policy.
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

/// Compiles [specs] into runtime policies.
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
