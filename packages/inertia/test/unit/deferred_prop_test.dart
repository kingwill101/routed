/// Tests for [DeferredProp] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs deferred prop unit tests.
void main() {
  group('DeferredProp', () {
    test('resolves when requested on partial reload', () {
      final prop = DeferredProp(() => 'deferred', group: 'custom');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['deferred'],
      );

      final value = prop.resolve('deferred', context);
      expect(value, equals('deferred'));
    });

    test('throws when not requested', () {
      final prop = DeferredProp(() => 'deferred', group: 'custom');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['other'],
      );

      expect(() => prop.resolve('deferred', context), throwsException);
    });

    test('skips on initial load', () {
      final prop = DeferredProp(() => 'deferred', group: 'custom');
      final context = PropertyContext(headers: {});

      expect(prop.shouldInclude('deferred', context), isFalse);
    });

    test('configures merge and deep merge options', () {
      final prop = DeferredProp(() => 'value', merge: true, deepMerge: true);

      expect(prop.shouldMerge, isTrue);
      expect(prop.shouldDeepMerge, isTrue);
    });

    test('configures once options', () {
      final prop = DeferredProp(
        () => 'value',
        once: true,
        ttl: Duration(seconds: 5),
        onceKey: 'custom',
        refresh: true,
      );

      expect(prop.shouldResolveOnce, isTrue);
      expect(prop.ttl, equals(Duration(seconds: 5)));
      expect(prop.onceKey, equals('custom'));
      expect(prop.shouldRefresh, isTrue);
    });

    test('uses provided group', () {
      final prop = DeferredProp(() => 'value', group: 'custom');

      expect(prop.group, equals('custom'));
    });
  });
}
