import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/events/rate_limit/rate_limit_events.dart';
import 'package:server_data/rate_limit.dart';

RateLimitEventCallbacks? rateLimitCallbacksForEvents(EventManager? events) {
  if (events == null) {
    return null;
  }
  return RateLimitEventCallbacks(
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
