import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/events/rate_limit/rate_limit_events.dart';
import 'package:routed/src/request.dart';
import 'package:server_data/rate_limit.dart' as server_data;
import 'package:server_data/rate_limit.dart'
    show CompiledRateLimitPolicy, RateLimitOutcome;

class RateLimitService {
  RateLimitService(
    List<CompiledRateLimitPolicy> policies, {
    EventManager? events,
  }) : _inner = server_data.RateLimitService(
         policies,
         callbacks: _callbacksFor(events),
       );

  final server_data.RateLimitService _inner;

  bool get enabled => _inner.enabled;

  void attachEvents(EventManager? events) {
    _inner.attachCallbacks(_callbacksFor(events));
  }

  Future<RateLimitOutcome?> check(Request request) {
    return _inner.check(request);
  }

  Future<void> dispose() => _inner.dispose();

  static server_data.RateLimitEventCallbacks? _callbacksFor(
    EventManager? events,
  ) {
    if (events == null) {
      return null;
    }
    return server_data.RateLimitEventCallbacks(
      onAllowed: (policy, strategy, identity, remaining, failoverMode) {
        events.publish(
          RateLimitAllowedEvent(
            policy: policy,
            strategy: strategy,
            identity: identity,
            remaining: remaining,
            failoverMode: failoverMode,
          ),
        );
      },
      onBlocked:
          (policy, strategy, identity, remaining, retryAfter, failoverMode) {
            events.publish(
              RateLimitBlockedEvent(
                policy: policy,
                strategy: strategy,
                identity: identity,
                remaining: remaining,
                retryAfter: retryAfter,
                failoverMode: failoverMode,
              ),
            );
          },
    );
  }
}
