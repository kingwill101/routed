import 'package:routed/src/events/event.dart';
import 'package:routed/src/rate_limit/policy.dart';

/// Base class for rate limit telemetry.
sealed class RateLimitEvent extends Event {
  RateLimitEvent({
    required this.policy,
    required this.strategy,
    required this.identity,
    required this.remaining,
    this.failoverMode,
  });

  /// Policy name that produced the outcome.
  final String policy;

  /// Strategy used for enforcement (token bucket, sliding window, quota).
  final RateLimitStrategy strategy;

  /// Identity string used for the evaluation.
  final String identity;

  /// Remaining quota tokens (if applicable).
  final int remaining;

  /// Optional failover mode if a fallback was triggered.
  final RateLimitFailoverMode? failoverMode;
}

/// Event emitted when a request is allowed.
final class RateLimitAllowedEvent extends RateLimitEvent {
  RateLimitAllowedEvent({
    required super.policy,
    required super.strategy,
    required super.identity,
    required super.remaining,
    super.failoverMode,
  });
}

/// Event emitted when a request is blocked.
final class RateLimitBlockedEvent extends RateLimitEvent {
  RateLimitBlockedEvent({
    required super.policy,
    required super.strategy,
    required super.identity,
    required super.remaining,
    required this.retryAfter,
    super.failoverMode,
  });

  /// Suggested retry-after interval.
  final Duration retryAfter;
}
