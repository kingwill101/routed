import 'package:routed/src/config/config.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:test/test.dart';

void main() {
  group('mergeConfigCandidates', () {
    test('later candidates override earlier keys', () {
      final config = ConfigImpl({
        'feature': {'enabled': true},
      });
      final merged = mergeConfigCandidates([
        const ConfigMapCandidate({'enabled': false, 'count': 1}, context: 'a'),
        const ConfigMapCandidate({'count': 2}, context: 'b'),
        ConfigMapCandidate.fromConfig(config, 'feature'),
      ]);

      expect(merged['enabled'], isTrue);
      expect(merged['count'], equals(2));
    });

    test('dropNulls skips null values while preserving others', () {
      final merged = mergeConfigCandidates(const [
        ConfigMapCandidate({'a': 1, 'b': null}, context: 'first'),
        ConfigMapCandidate({'b': 2}, context: 'second'),
      ], dropNulls: true);
      expect(merged, equals({'a': 1, 'b': 2}));
    });
  });

  group('parsing helpers', () {
    test('parseBoolLike accepts string variants', () {
      expect(parseBoolLike('true', context: 'flag'), isTrue);
      expect(parseBoolLike('Off', context: 'flag'), isFalse);
      expect(parseBoolLike(null, context: 'flag'), isNull);
    });

    test('parseIntLike parses numeric strings', () {
      expect(parseIntLike('42', context: 'answer'), equals(42));
      expect(parseIntLike(7, context: 'answer'), equals(7));
    });

    test('parseStringList handles comma separated strings', () {
      expect(
        parseStringList('foo, bar ,baz', context: 'list'),
        equals(['foo', 'bar', 'baz']),
      );
    });

    test('parseStringList coerces non-string entries when enabled', () {
      expect(
        parseStringList(
          [1, 'two', 3],
          context: 'list',
          coerceNonStringEntries: true,
        ),
        equals(['1', 'two', '3']),
      );
    });

    test('parseStringSet returns lower-cased unique entries', () {
      expect(
        parseStringSet(['A', 'b', 'a'], context: 'set', toLowerCase: true),
        equals({'a', 'b'}),
      );
    });

    test('parseStringMap coerceValues converts non-string entries', () {
      final map = parseStringMap(
        {'one': 1, 'two': '2'},
        context: 'map',
        coerceValues: true,
      );
      expect(map, equals({'one': '1', 'two': '2'}));
    });

    test('stringKeyedMap converts Config to map', () {
      final config = ConfigImpl({
        'nested': {'key': 'value'},
      });
      final map = stringKeyedMap(config.get('nested') as Object, 'nested');
      expect(map, equals({'key': 'value'}));
    });
  });
}
