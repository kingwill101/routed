/// Tests for [PageData] construction and serialization.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia_dart.dart';

/// Runs page data unit tests.
void main() {
  group('PageData', () {
    test('builds from context headers', () {
      final page = PageData.fromContext(
        'Home',
        {'name': 'Ada'},
        '/home',
        {'X-Inertia-Version': '123', 'X-Inertia-History': 'encrypt,clear'},
      );

      expect(page.version, equals('123'));
      expect(page.encryptHistory, isTrue);
      expect(page.clearHistory, isTrue);
    });

    test('serializes optional fields', () {
      final page = PageData(
        component: 'Home',
        props: {'name': 'Ada'},
        url: '/home',
        deferredProps: {
          'default': ['lazy'],
        },
        mergeProps: ['merge'],
        deepMergeProps: ['deep'],
        prependProps: ['prepend'],
        matchPropsOn: ['merge.id'],
        scrollProps: {
          'items': {
            'pageName': 'page',
            'previousPage': 1,
            'nextPage': 3,
            'currentPage': 2,
            'reset': false,
          },
        },
        onceProps: {
          'token': {'prop': 'token', 'expiresAt': null},
        },
        flash: {'notice': 'Saved'},
        cache: [30],
      );

      final json = page.toJson();
      expect(json['deferredProps'], isNotNull);
      expect(json['mergeProps'], equals(['merge']));
      expect(json['deepMergeProps'], equals(['deep']));
      expect(json['prependProps'], equals(['prepend']));
      expect(json['matchPropsOn'], equals(['merge.id']));
      expect(json['scrollProps'], isNotNull);
      expect(json['onceProps'], isNotNull);
      expect(json['flash'], equals({'notice': 'Saved'}));
      expect(json['cache'], equals([30]));
    });
  });
}
