import 'package:routed/src/utils/dot.dart';
import 'package:test/test.dart';

void main() {
  group('Dot', () {
    test('get returns nested value using dotted path', () {
      final map = <String, dynamic>{
        'level1': <String, dynamic>{
          'level2': <String, dynamic>{'value': 42},
        },
      };
      expect(dot.get(map, 'level1.level2.value'), equals(42));
      expect(dot(map).get('level1.level2.value'), equals(42));
    });

    test('get returns entire map when path is empty', () {
      final map = <String, dynamic>{'foo': 1};
      expect(identical(dot.get(map, ''), map), isTrue);
    });

    test('get returns null when path missing', () {
      expect(dot.get(<String, dynamic>{}, 'missing.key'), isNull);
    });

    test('context contains mirrors global contains', () {
      final map = <String, dynamic>{
        'foo': {'bar': 1},
      };
      expect(dot.contains(map, 'foo.bar'), isTrue);
      expect(dot(map).contains('foo.bar'), isTrue);
      expect(dot.contains(map, 'foo.baz'), isFalse);
    });

    test('set creates nested maps based on dotted path', () {
      final map = <String, dynamic>{};
      dot.set(map, 'a.b.c', 10);
      expect(
        map,
        equals({
          'a': {
            'b': {'c': 10},
          },
        }),
      );
    });

    test('set replaces scalar intermediates with maps as needed', () {
      final map = <String, dynamic>{'a': 5};
      dot.set(map, 'a.b', 10);
      dot(map).set('a.b.c', 20);
      expect(
        map,
        equals({
          'a': {
            'b': {'c': 20},
          },
        }),
      );
    });

    test('set merges map values rather than overwriting entire branch', () {
      final map = <String, dynamic>{
        'http': <String, dynamic>{
          'middleware_sources': <String, dynamic>{
            'routed.sessions': <String, dynamic>{
              'global': <String>['routed.sessions.start'],
            },
          },
        },
      };

      dot.set(map, 'http.middleware_sources', <String, dynamic>{
        'routed.sessions': <String, dynamic>{
          'groups': <String, dynamic>{
            'web': <String>['routed.sessions.start'],
          },
        },
        'routed.logging': <String, dynamic>{
          'global': <String>['routed.logging.http'],
        },
      });

      expect(
        map,
        equals({
          'http': {
            'middleware_sources': {
              'routed.sessions': {
                'global': ['routed.sessions.start'],
                'groups': {
                  'web': ['routed.sessions.start'],
                },
              },
              'routed.logging': {
                'global': ['routed.logging.http'],
              },
            },
          },
        }),
      );
    });

    test('set coerces non-string map keys and nested structures', () {
      final map = <String, dynamic>{};
      dot.set(map, 'metrics', {
        1: {
          'thresholds': [1, 2],
        },
        'list': {0: 'a', 1: 'b'},
      });
      expect(
        map,
        equals({
          'metrics': {
            '1': {
              'thresholds': [1, 2],
            },
            'list': {'0': 'a', '1': 'b'},
          },
        }),
      );
    });
  });
}
