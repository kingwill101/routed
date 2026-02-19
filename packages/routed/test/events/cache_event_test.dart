import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('CacheEvent hierarchy', () {
    test('CacheHitEvent stores store and key', () {
      final event = CacheHitEvent(store: 'redis', key: 'user:42');

      expect(event.store, equals('redis'));
      expect(event.key, equals('user:42'));
      expect(event.timestamp, isA<DateTime>());
      expect(event, isA<CacheEvent>());
      expect(event, isA<Event>());
    });

    test('CacheMissEvent stores store and key', () {
      final event = CacheMissEvent(store: 'memory', key: 'session:abc');

      expect(event.store, equals('memory'));
      expect(event.key, equals('session:abc'));
      expect(event.timestamp, isA<DateTime>());
      expect(event, isA<CacheEvent>());
    });

    test('CacheWriteEvent stores store, key, and optional ttl', () {
      final withTtl = CacheWriteEvent(
        store: 'redis',
        key: 'token:xyz',
        ttl: const Duration(minutes: 15),
      );

      expect(withTtl.store, equals('redis'));
      expect(withTtl.key, equals('token:xyz'));
      expect(withTtl.ttl, equals(const Duration(minutes: 15)));
      expect(withTtl, isA<CacheEvent>());

      final withoutTtl = CacheWriteEvent(store: 'memory', key: 'data:1');

      expect(withoutTtl.ttl, isNull);
    });

    test('CacheForgetEvent stores store and key', () {
      final event = CacheForgetEvent(store: 'redis', key: 'stale:entry');

      expect(event.store, equals('redis'));
      expect(event.key, equals('stale:entry'));
      expect(event.timestamp, isA<DateTime>());
      expect(event, isA<CacheEvent>());
    });

    test('CacheEvent is sealed — all subclasses are final', () {
      // Verify exhaustive pattern matching works (compile-time check)
      CacheEvent event = CacheHitEvent(store: 's', key: 'k');
      final label = switch (event) {
        CacheHitEvent() => 'hit',
        CacheMissEvent() => 'miss',
        CacheWriteEvent() => 'write',
        CacheForgetEvent() => 'forget',
      };
      expect(label, equals('hit'));
    });

    test('timestamps are close to now', () {
      final before = DateTime.now();
      final event = CacheHitEvent(store: 's', key: 'k');
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

    test('different instances have independent timestamps', () async {
      final first = CacheHitEvent(store: 's', key: 'k');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = CacheMissEvent(store: 's', key: 'k');

      expect(
        second.timestamp.millisecondsSinceEpoch,
        greaterThan(first.timestamp.millisecondsSinceEpoch),
      );
    });
  });
}
