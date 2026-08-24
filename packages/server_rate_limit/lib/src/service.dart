import 'dart:async';

import 'package:server_rate_limit/src/backend.dart';
import 'package:server_rate_limit/src/policy.dart';

/// Optional callbacks for observing rate-limit outcomes.
class RateLimitEventCallbacks {
  /// Creates callbacks for allowed and blocked evaluations.
  const RateLimitEventCallbacks({this.onAllowed, this.onBlocked});

  /// Called after a policy allows a request.
  final void Function(
    String policy,
    RateLimitStrategy strategy,
    String identity,
    int remaining,
    RateLimitFailoverMode? failoverMode,
  )?
  onAllowed;

  /// Called after a policy blocks a request.
  final void Function(
    String policy,
    RateLimitStrategy strategy,
    String identity,
    int remaining,
    Duration retryAfter,
    RateLimitFailoverMode? failoverMode,
  )?
  onBlocked;
}

/// Evaluates compiled policies for incoming requests.
class RateLimitService {
  /// Creates a service for the supplied policies.
  ///
  /// [callbacks] receives notifications after matching policies are evaluated.
  RateLimitService(this._policies, {RateLimitEventCallbacks? callbacks})
    : _callbacks = callbacks;

  final List<CompiledRateLimitPolicy> _policies;
  RateLimitEventCallbacks? _callbacks;

  /// Whether this service has at least one policy to evaluate.
  bool get enabled => _policies.isNotEmpty;

  /// Replaces the callbacks used for subsequent evaluations.
  // This remains a method because callback attachment is an explicit service
  // lifecycle operation rather than a field assignment.
  // ignore: use_setters_to_change_properties
  void attachCallbacks(RateLimitEventCallbacks? callbacks) {
    _callbacks = callbacks;
  }

  /// Evaluates [request] and returns the first blocking outcome.
  ///
  /// Returns `null` when no policy matches or all matching policies allow the
  /// request.
  Future<RateLimitOutcome?> check(RateLimitRequest request) async {
    if (_policies.isEmpty) return null;
    RateLimitOutcome? blocked;
    final now = DateTime.now();
    final callbacks = _callbacks;

    for (final policy in _policies) {
      if (!policy.matches(request)) {
        continue;
      }
      final identity = policy.keyResolver.resolve(request);
      if (identity == null || identity.isEmpty) {
        continue;
      }
      final outcome = await policy.evaluate(identity, now);
      if (callbacks != null) {
        _publishCallbacks(callbacks, policy, identity, outcome);
      }
      if (!outcome.allowed) {
        blocked = outcome;
        break;
      }
    }
    return blocked;
  }

  /// Closes each distinct backend used by this service.
  Future<void> dispose() async {
    final closed = <RateLimiterBackend>{};
    for (final policy in _policies) {
      if (closed.add(policy.backend)) {
        await policy.backend.close();
      }
    }
    _callbacks = null;
  }

  void _publishCallbacks(
    RateLimitEventCallbacks callbacks,
    CompiledRateLimitPolicy policy,
    String identity,
    RateLimitOutcome outcome,
  ) {
    final remaining = outcome.remaining;
    final strategy = policy.algorithm.strategy;
    final failover = outcome.failoverMode;
    if (outcome.allowed) {
      callbacks.onAllowed?.call(
        policy.name,
        strategy,
        identity,
        remaining,
        failover,
      );
      return;
    }
    callbacks.onBlocked?.call(
      policy.name,
      strategy,
      identity,
      remaining,
      outcome.retryAfter,
      failover,
    );
  }
}
