import 'package:routed/src/config/config.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigImpl', () {
    test('supports dotted keys for get and set', () {
      final config = ConfigImpl();
      config.set('app.name', 'Test App');
      config.set('app.debug', true);

      expect(config.has('app.name'), isTrue);
      expect(config.get('app.name'), equals('Test App'));
      expect(config.get('app.debug'), isTrue);
      expect(config.get('app.missing', 'default'), equals('default'));
    });

    test('merge handles dotted keys and nested maps', () {
      final config = ConfigImpl({
        'app': {
          'name': 'Base App',
          'features': {'a': true},
        },
      });

      config.merge({
        'app.name': 'Override App',
        'app.features': {'b': false},
        'db': {'host': 'localhost'},
      });

      expect(config.get('app.name'), equals('Override App'));
      expect(config.get('app.features.a'), isTrue);
      expect(config.get('app.features.b'), isFalse);
      expect(config.get('db.host'), equals('localhost'));
      expect(config.get('db'), isA<Map<String, dynamic>>());
    });

    test('list helpers create and manipulate arrays', () {
      final config = ConfigImpl();
      config.push('services', 'first');
      config.push('services', 'second');
      config.prepend('services', 'zero');

      expect(config.get('services'), equals(['zero', 'first', 'second']));
    });

    test('getOrThrow throws with helpful error', () {
      final config = ConfigImpl();
      expect(() => config.getOrThrow<String>('missing'), throwsStateError);
    });
  });
}
