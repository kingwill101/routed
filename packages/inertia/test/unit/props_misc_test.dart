/// Tests for assorted prop helpers.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs miscellaneous prop unit tests.
void main() {
  group('Misc Props', () {
    test('AlwaysProp resolves once', () {
      var count = 0;
      final prop = AlwaysProp(() {
        count += 1;
        return 'value';
      });

      final context = PropertyContext(headers: {});
      expect(prop.resolve('always', context), equals('value'));
      expect(prop.resolve('always', context), equals('value'));
      expect(count, equals(1));
    });

    test('AlwaysProp returns string values', () {
      final prop = AlwaysProp(() => 'date');
      final context = PropertyContext(headers: {});

      expect(prop.resolve('always', context), equals('date'));
    });

    test('OnceProp resolves each time', () {
      var count = 0;
      final prop = OnceProp(() {
        count += 1;
        return count;
      }, ttl: Duration(milliseconds: 5));

      final context = PropertyContext(headers: {});
      expect(prop.resolve('once', context), equals(1));
      expect(prop.resolve('once', context), equals(2));
    });

    test('ScrollProp resolves value', () {
      final prop = ScrollProp(() => {'y': 120});
      final context = PropertyContext(headers: {});
      expect(prop.resolve('scroll', context), equals({'y': 120}));
    });

    test('ScrollProp resolves once', () {
      var count = 0;
      final prop = ScrollProp(() {
        count += 1;
        return ['item'];
      });
      final context = PropertyContext(headers: {});

      prop.resolve('scroll', context);
      prop.resolve('scroll', context);

      expect(count, equals(1));
    });
  });

  group('Shared Props', () {
    test('stores and merges values', () {
      final shared = InertiaSharedProps();
      shared.addAll({'name': 'Ada'});
      shared.set('team', 'Math');

      expect(shared.isEmpty, isFalse);
      expect(shared.all(), equals({'name': 'Ada', 'team': 'Math'}));
    });
  });
}
