/// Tests for [MergeProp] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs merge prop unit tests.
void main() {
  group('MergeProp', () {
    test('defaults to root append', () {
      final prop = MergeProp(() => 'value');

      expect(prop.shouldMerge, isTrue);
      expect(prop.appendsAtRoot, isTrue);
      expect(prop.prependsAtRoot, isFalse);
    });

    test('resolves string values when included', () {
      final prop = MergeProp(() => 'date');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['merge'],
      );

      final value = prop.resolve('merge', context);
      expect(value, equals('date'));
    });

    test('supports root prepend', () {
      final prop = MergeProp(() => 'value')..prepend();

      expect(prop.prependsAtRoot, isTrue);
      expect(prop.appendsAtRoot, isFalse);
      expect(prop.appendsAtPaths, isEmpty);
      expect(prop.prependsAtPaths, isEmpty);
    });

    test('collects append and prepend paths', () {
      final prop = MergeProp(() => 'value')
        ..append(['items', 'data'])
        ..prepend(['meta']);

      expect(prop.appendsAtRoot, isFalse);
      expect(prop.prependsAtRoot, isFalse);
      expect(prop.appendsAtPaths, contains('items'));
      expect(prop.appendsAtPaths, contains('data'));
      expect(prop.prependsAtPaths, contains('meta'));
    });

    test('records match-on paths', () {
      final prop = MergeProp(() => 'value')
        ..append('items', 'id')
        ..prepend('meta', 'uuid')
        ..matchOn(['extra', 'another']);

      expect(prop.matchesOn, contains('items.id'));
      expect(prop.matchesOn, contains('meta.uuid'));
      expect(prop.matchesOn, contains('extra'));
      expect(prop.matchesOn, contains('another'));
    });

    test('configures deep merge', () {
      final prop = MergeProp(() => 'value', deepMerge: true);

      expect(prop.shouldMerge, isTrue);
      expect(prop.shouldDeepMerge, isTrue);
    });

    test('configures once options', () {
      final prop = MergeProp(
        () => 'value',
        once: true,
        ttl: Duration(seconds: 2),
        onceKey: 'token',
        refresh: true,
      );

      expect(prop.shouldResolveOnce, isTrue);
      expect(prop.ttl, equals(Duration(seconds: 2)));
      expect(prop.onceKey, equals('token'));
      expect(prop.shouldRefresh, isTrue);
    });
  });
}
