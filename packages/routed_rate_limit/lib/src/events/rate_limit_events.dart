import 'package:routed_core/routed_core.dart' show Event;
import 'package:server_rate_limit/server_rate_limit.dart';

/// Base class for telemetry describing a rate-limit evaluation.
///
/// These objects are immutable event data; constructing one does not publish
/// it to an event bus. Applications can create them from
/// [RateLimitEventCallbacks] and forward them to their telemetry system.
/// [identity] may contain an IP address or a caller-supplied header value, so
/// applications should apply their normal privacy and retention rules before
/// recording it.
sealed class RateLimitEvent extends Event {
  RateLimitEvent({
    required this.policy,
    required this.strategy,
    required this.identity,
    required this.remaining,
    this.failoverMode,
  });

  /// Stable policy name that produced the outcome.
  final String policy;

  /// Strategy used for enforcement.
  final RateLimitStrategy strategy;

  /// Identity string used to select the caller's rate-limit bucket.
  final String identity;

  /// Requests or tokens remaining after the evaluation.
  final int remaining;

  /// Failover mode used when the primary backend was unavailable, if any.
  final RateLimitFailoverMode? failoverMode;
}

/// Describes an evaluation that allowed a request.
///
/// The event is not emitted automatically by this package. Use it as the
/// payload for an application's callback or telemetry adapter.
final class RateLimitAllowedEvent extends RateLimitEvent {
  /// Creates an event for an allowed request.
  RateLimitAllowedEvent({
    required super.policy,
    required super.strategy,
    required super.identity,
    required super.remaining,
    super.failoverMode,
  });
}

/// Describes an evaluation that blocked a request.
///
/// [retryAfter] is the policy's suggested delay before a retry; it is not a
/// guarantee that the next request will be accepted, because other matching
/// policies or concurrent requests may still apply.
final class RateLimitBlockedEvent extends RateLimitEvent {
  /// Creates an event for a blocked request.
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
