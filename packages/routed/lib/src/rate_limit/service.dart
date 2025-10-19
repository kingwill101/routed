import 'dart:async';

import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/events/rate_limit/rate_limit_events.dart';
import 'package:routed/src/request.dart';

import 'policy.dart';
import 'backend.dart';

class RateLimitService {
  RateLimitService(this._policies, {EventManager? events}) : _events = events;

  final List<CompiledRateLimitPolicy> _policies;
  EventManager? _events;

  bool get enabled => _policies.isNotEmpty;

  void attachEvents(EventManager? events) {
    _events = events;
  }

  Future<RateLimitOutcome?> check(Request request) async {
    if (_policies.isEmpty) return null;
    RateLimitOutcome? blocked;
    final now = DateTime.now();
    final events = _events;

    for (final policy in _policies) {
      if (!policy.matches(request)) {
        continue;
      }
      final identity = policy.keyResolver.resolve(request);
      if (identity == null || identity.isEmpty) {
        continue;
      }
      final outcome = await policy.evaluate(identity, now);
      if (events != null) {
        _publishEvent(events, policy, identity, outcome);
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
    _events = null;
  }

  void _publishEvent(
    EventManager events,
    CompiledRateLimitPolicy policy,
    String identity,
    RateLimitOutcome outcome,
  ) {
    final remaining = outcome.remaining;
    final strategy = policy.algorithm.strategy;
    final failover = outcome.failoverMode;
    final event = outcome.allowed
        ? RateLimitAllowedEvent(
            policy: policy.name,
            strategy: strategy,
            identity: identity,
            remaining: remaining,
            failoverMode: failover,
          )
        : RateLimitBlockedEvent(
            policy: policy.name,
            strategy: strategy,
            identity: identity,
            remaining: remaining,
            retryAfter: outcome.retryAfter,
            failoverMode: failover,
          );
    events.publish(event);
  }
}
