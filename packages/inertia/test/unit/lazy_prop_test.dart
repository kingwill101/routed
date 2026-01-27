/// Tests for [LazyProp] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia_dart.dart';

/// Runs lazy prop unit tests.
void main() {
  group('LazyProp', () {
    test('resolves value when requested on partial reload', () {
      final prop = LazyProp(() => 'lazy-value');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['lazy'],
      );

      final value = prop.resolve('lazy', context);
      expect(value, equals('lazy-value'));
    });

    test('resolves string values', () {
      final prop = LazyProp(() => 'date');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['lazy'],
      );

      final value = prop.resolve('lazy', context);
      expect(value, equals('date'));
    });

    test('skips value on partial reload when not requested', () {
      final prop = LazyProp(() => 'lazy-value');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['other'],
      );

      expect(() => prop.resolve('lazy', context), throwsException);
    });

    test('skips value on initial load', () {
      final prop = LazyProp(() => 'lazy-value');
      final context = PropertyContext(headers: {});

      expect(() => prop.resolve('lazy', context), throwsException);
    });
  });
}
