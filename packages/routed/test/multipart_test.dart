import 'package:routed/src/binding/utils.dart';
import 'package:test/test.dart';

void main() {
  group('parseUrlEncoded comprehensive tests', () {
    test('should parse simple key-value pairs', () {
      final input = 'key1=value1&key2=value2';
      final result = parseUrlEncoded(input);

      expect(result['key1'], equals('value1'));
      expect(result['key2'], equals('value2'));
    });

    test('should handle arrays with bracket notation', () {
      final input = 'items[]=item1&items[]=item2&items[]=item3';
      final result = parseUrlEncoded(input);

      expect(result['items'], equals(['item1', 'item2', 'item3']));
    });

    test('should parse nested maps', () {
      final input =
          'user[name]=John&user[details][age]=25&user[details][city]=NY';
      final result = parseUrlEncoded(input);

      expect(result['user']['name'], equals('John'));
      expect(result['user']['details']['age'], equals('25'));
      expect(result['user']['details']['city'], equals('NY'));
    });

    test('should handle mixed arrays and nested maps', () {
      final input =
          'user[hobbies][]=reading&user[hobbies][]=sports&user[details][languages][]=English&user[details][languages][]=Spanish';
      final result = parseUrlEncoded(input);

      expect(result['user']['hobbies'], equals(['reading', 'sports']));
      expect(
        result['user']['details']['languages'],
        equals(['English', 'Spanish']),
      );
    });

    test('should decode special characters', () {
      final input = 'special=%40%23%24%25%5E%26*()';
      final result = parseUrlEncoded(input);

      expect(result['special'], equals('@#\$%^&*()'));
    });

    test('should handle empty values', () {
      final input = 'emptyKey=&anotherEmpty=';
      final result = parseUrlEncoded(input);

      expect(result['emptyKey'], equals(''));
      expect(result['anotherEmpty'], equals(''));
    });

    test('should handle repeated keys with different structures', () {
      final input = 'key=value1&key[]=value2&key[nested]=value3';
      final result = parseUrlEncoded(input);

      expect(
        result['key'],
        equals([
          'value1',
          'value2',
          {'nested': 'value3'},
        ]),
      );
    });

    test('should handle complex nested structures', () {
      final input =
          'user[info][name]=Alice&user[info][contacts][email]=alice@example.com&user[info][contacts][phone]=1234567890&user[preferences][]=dark_mode&user[preferences][]=notifications';
      final result = parseUrlEncoded(input);

      expect(result['user']['info']['name'], equals('Alice'));
      expect(
        result['user']['info']['contacts']['email'],
        equals('alice@example.com'),
      );
      expect(result['user']['info']['contacts']['phone'], equals('1234567890'));
      expect(
        result['user']['preferences'],
        equals(['dark_mode', 'notifications']),
      );
    });
  });
}
