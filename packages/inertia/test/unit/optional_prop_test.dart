/// Tests for [OptionalProp] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia_dart.dart';

/// Runs optional prop unit tests.
void main() {
  group('OptionalProp', () {
    test('resolves only on partial reload when requested', () {
      final prop = OptionalProp(() => 'value');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['optional'],
      );

      final value = prop.resolve('optional', context);
      expect(value, equals('value'));
    });

    test('resolves string values', () {
      final prop = OptionalProp(() => 'date');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['optional'],
      );

      final value = prop.resolve('optional', context);
      expect(value, equals('date'));
    });

    test('throws when not requested on partial reload', () {
      final prop = OptionalProp(() => 'value');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['other'],
      );

      expect(() => prop.resolve('optional', context), throwsException);
    });

    test('configures once options', () {
      final prop = OptionalProp(
        () => 'value',
        once: true,
        ttl: Duration(seconds: 10),
        onceKey: 'token',
        refresh: true,
      );

      expect(prop.shouldResolveOnce, isTrue);
      expect(prop.ttl, equals(Duration(seconds: 10)));
      expect(prop.onceKey, equals('token'));
      expect(prop.shouldRefresh, isTrue);
    });

    test('supports fluent once configuration', () {
      final prop = OptionalProp(() => 'value')
        ..once(key: 'custom', ttl: Duration(seconds: 5))
        ..fresh()
        ..withKey('override');

      expect(prop.shouldResolveOnce, isTrue);
      expect(prop.ttl, equals(Duration(seconds: 5)));
      expect(prop.onceKey, equals('override'));
      expect(prop.shouldRefresh, isTrue);
    });
  });
}
