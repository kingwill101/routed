import 'dart:async';

import 'backend.dart';
import 'policy.dart';

/// Optional callbacks for publishing rate-limit outcomes.
class RateLimitEventCallbacks {
  const RateLimitEventCallbacks({this.onAllowed, this.onBlocked});

  final void Function(
    String policy,
    RateLimitStrategy strategy,
    String identity,
    int remaining,
    RateLimitFailoverMode? failoverMode,
  )?
  onAllowed;

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

class RateLimitService {
  RateLimitService(this._policies, {RateLimitEventCallbacks? callbacks})
    : _callbacks = callbacks;

  final List<CompiledRateLimitPolicy> _policies;
  RateLimitEventCallbacks? _callbacks;

  bool get enabled => _policies.isNotEmpty;

  void attachCallbacks(RateLimitEventCallbacks? callbacks) {
    _callbacks = callbacks;
  }

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
