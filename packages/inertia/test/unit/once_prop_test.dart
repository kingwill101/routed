/// Tests for [OnceProp] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs once prop unit tests.
void main() {
  group('OnceProp', () {
    test('configures once options from constructor', () {
      final prop = OnceProp(
        () => 'value',
        ttl: Duration(seconds: 3),
        key: 'token',
        refresh: true,
      );

      expect(prop.shouldResolveOnce, isTrue);
      expect(prop.ttl, equals(Duration(seconds: 3)));
      expect(prop.onceKey, equals('token'));
      expect(prop.shouldRefresh, isTrue);
    });

    test('resolves string values', () {
      final prop = OnceProp(() => 'date');
      final context = PropertyContext(headers: {});

      final value = prop.resolve('once', context);
      expect(value, equals('date'));
    });

    test('supports fluent once configuration', () {
      final prop = OnceProp(() => 'value')
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
