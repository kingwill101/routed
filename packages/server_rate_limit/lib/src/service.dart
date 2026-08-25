import 'dart:async';

import 'package:server_rate_limit/src/backend.dart';
import 'package:server_rate_limit/src/policy.dart';

/// Optional callbacks for observing rate-limit outcomes.
///
/// Callbacks run after a matching policy has consumed or rejected its quota.
/// Keep them non-blocking where possible; callback failures are not converted
/// into rate-limit decisions.
class RateLimitEventCallbacks {
  /// Creates callbacks for allowed and blocked evaluations.
  const RateLimitEventCallbacks({this.onAllowed, this.onBlocked});

  /// Called after a policy allows a request.
  ///
  /// `remaining` is the post-evaluation count or token estimate. A non-null
  /// `failoverMode` indicates that the backend was unavailable and the
  /// configured failover behavior produced this result.
  final void Function(
    String policy,
    RateLimitStrategy strategy,
    String identity,
    int remaining,
    RateLimitFailoverMode? failoverMode,
  )?
  onAllowed;

  /// Called after a policy blocks a request.
  ///
  /// `retryAfter` is the backend's suggested delay. A non-null
  /// `failoverMode` identifies a fail-closed or fallback decision rather than
  /// a normal backend evaluation.
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
///
/// Matching policies are evaluated in list order. Every matching policy with a
/// resolvable identity consumes its own allowance until one blocks the
/// request; therefore a request can consume multiple policy quotas.
class RateLimitService {
  /// Creates a service for the supplied policies.
  ///
  /// `policies` are evaluated in their supplied order. [callbacks] receives
  /// notifications after matching policies are evaluated.
  RateLimitService(this._policies, {RateLimitEventCallbacks? callbacks})
    : _callbacks = callbacks;

  final List<CompiledRateLimitPolicy> _policies;
  RateLimitEventCallbacks? _callbacks;

  /// Whether this service has at least one policy to evaluate.
  bool get enabled => _policies.isNotEmpty;

  /// Replaces the callbacks used for subsequent evaluations.
  ///
  /// Pass `null` to stop publishing events. This does not change the policies
  /// or reset their backend state.
  // This remains a method because callback attachment is an explicit service
  // lifecycle operation rather than a field assignment.
  // ignore: use_setters_to_change_properties
  void attachCallbacks(RateLimitEventCallbacks? callbacks) {
    _callbacks = callbacks;
  }

  /// Evaluates [request] and returns the first blocking outcome.
  ///
  /// Returns `null` when no policy matches, no matching policy can resolve an
  /// identity, or all matching policies allow the request. Matching policies
  /// may still consume quota before a later policy blocks the request.
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
  ///
  /// Each backend instance is closed at most once. For
  /// [CacheRateLimiterBackend], this does not close the application-owned
  /// repository.
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
