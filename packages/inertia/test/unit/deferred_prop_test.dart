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
  });
}
