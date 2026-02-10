import 'package:routed/routed.dart';
import 'package:routed/src/rate_limit/policy.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('RateLimitEvent hierarchy', () {
    test('RateLimitAllowedEvent stores all fields', () {
      final event = RateLimitAllowedEvent(
        policy: 'global',
        strategy: RateLimitStrategy.tokenBucket,
        identity: '192.168.1.1',
        remaining: 7,
      );

      expect(event.policy, equals('global'));
      expect(event.strategy, equals(RateLimitStrategy.tokenBucket));
      expect(event.identity, equals('192.168.1.1'));
      expect(event.remaining, equals(7));
      expect(event.failoverMode, isNull);
      expect(event.timestamp, isA<DateTime>());
      expect(event, isA<RateLimitEvent>());
      expect(event, isA<Event>());
    });

    test('RateLimitAllowedEvent with failover mode', () {
      final event = RateLimitAllowedEvent(
        policy: 'api',
        strategy: RateLimitStrategy.slidingWindow,
        identity: 'key:abc',
        remaining: 0,
        failoverMode: RateLimitFailoverMode.local,
      );

      expect(event.failoverMode, equals(RateLimitFailoverMode.local));
      expect(event.strategy, equals(RateLimitStrategy.slidingWindow));
    });

    test('RateLimitBlockedEvent stores all fields including retryAfter', () {
      final event = RateLimitBlockedEvent(
        policy: 'auth',
        strategy: RateLimitStrategy.slidingWindow,
        identity: '10.0.0.1',
        remaining: 0,
        retryAfter: Duration(seconds: 30),
      );

      expect(event.policy, equals('auth'));
      expect(event.strategy, equals(RateLimitStrategy.slidingWindow));
      expect(event.identity, equals('10.0.0.1'));
      expect(event.remaining, equals(0));
      expect(event.retryAfter, equals(Duration(seconds: 30)));
      expect(event.failoverMode, isNull);
      expect(event, isA<RateLimitEvent>());
    });

    test('RateLimitBlockedEvent with failover mode', () {
      final event = RateLimitBlockedEvent(
        policy: 'quota',
        strategy: RateLimitStrategy.quota,
        identity: 'user:42',
        remaining: 0,
        retryAfter: Duration(hours: 1),
        failoverMode: RateLimitFailoverMode.block,
      );

      expect(event.strategy, equals(RateLimitStrategy.quota));
      expect(event.retryAfter, equals(Duration(hours: 1)));
      expect(event.failoverMode, equals(RateLimitFailoverMode.block));
    });

    test('RateLimitEvent is sealed — exhaustive matching', () {
      RateLimitEvent event = RateLimitAllowedEvent(
        policy: 'p',
        strategy: RateLimitStrategy.tokenBucket,
        identity: 'id',
        remaining: 5,
      );

      final label = switch (event) {
        RateLimitAllowedEvent() => 'allowed',
        RateLimitBlockedEvent() => 'blocked',
      };
      expect(label, equals('allowed'));
    });

    test('all three strategies can be used', () {
      for (final strategy in RateLimitStrategy.values) {
        final event = RateLimitAllowedEvent(
          policy: 'test',
          strategy: strategy,
          identity: 'x',
          remaining: 1,
        );
        expect(event.strategy, equals(strategy));
      }
    });

    test('all three failover modes can be used', () {
      for (final mode in RateLimitFailoverMode.values) {
        final event = RateLimitAllowedEvent(
          policy: 'test',
          strategy: RateLimitStrategy.tokenBucket,
          identity: 'x',
          remaining: 1,
          failoverMode: mode,
        );
        expect(event.failoverMode, equals(mode));
      }
    });

    test('timestamps are close to now', () {
      final before = DateTime.now();
      final event = RateLimitBlockedEvent(
        policy: 'p',
        strategy: RateLimitStrategy.tokenBucket,
        identity: 'id',
        remaining: 0,
        retryAfter: Duration(seconds: 10),
      );
      final after = DateTime.now();

      expect(
        event.timestamp.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
      expect(
        event.timestamp.millisecondsSinceEpoch,
        lessThanOrEqualTo(after.millisecondsSinceEpoch),
      );
    });
  });
}
