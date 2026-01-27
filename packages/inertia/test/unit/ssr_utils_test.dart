/// Tests for SSR CLI utilities.
library;

import 'package:inertia_dart/src/cli/ssr_utils.dart';
import 'package:test/test.dart';

void main() {
  group('SSR CLI utilities', () {
    test('normalizeSsrBase strips render path', () {
      final base = normalizeSsrBase('http://localhost:13714/render');
      expect(base.toString(), equals('http://localhost:13714/'));

      final nested = normalizeSsrBase('http://localhost:13714/api/render');
      expect(nested.path, equals('/api'));
    });

    test('normalizeSsrBase preserves non-render path', () {
      final base = normalizeSsrBase('http://localhost:13714/api');
      expect(base.path, equals('/api'));
    });

    test('parseEnvironment ignores invalid entries', () {
      final env = parseEnvironment([
        'FOO=bar',
        'EMPTY=',
        '=invalid',
        'nope',
        'NAME=value=with=equals',
      ]);

      expect(
        env,
        equals({'FOO': 'bar', 'EMPTY': '', 'NAME': 'value=with=equals'}),
      );
    });
  });
}
