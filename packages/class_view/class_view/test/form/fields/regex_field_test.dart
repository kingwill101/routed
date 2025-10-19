import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

void main() {
  group('RegexField Tests', () {
    test('basic regex validation', () async {
      final f = RegexField(RegExp(r'^[0-9][A-F][0-9]$'));

      expect(f.toDart('2A2'), equals('2A2'));
      expect(f.toDart('3F3'), equals('3F3'));

      expect(
        () => f.validate('3G3'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );

      expect(
        () => f.validate(' 2A2'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );

      expect(
        () => f.validate('2A2 '),
        throwsA(containsErrorMessage('Enter a valid value')),
      );

      expect(
        () => f.validate(''),
        throwsA(containsErrorMessage('This field is required')),
      );
    });

    test('regex field with required=false', () async {
      final f = RegexField(RegExp(r'^[0-9][A-F][0-9]$'), required: false);

      expect(f.toDart('2A2'), equals('2A2'));
      expect(f.toDart('3F3'), equals('3F3'));

      expect(
        () => f.validate('3G3'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );

      expect(f.toDart(''), isNull);
    });

    test('regex field with string pattern', () async {
      final f = RegexField(r'^[0-9][A-F][0-9]$');

      expect(f.toDart('2A2'), equals('2A2'));
      expect(f.toDart('3F3'), equals('3F3'));

      expect(
        () => f.validate('3G3'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );
    });

    test('regex field with min and max length', () async {
      final f = RegexField(r'^[0-9]+$', minLength: 5, maxLength: 10);

      expect(
        () => f.validate('123'),
        throwsA(
          containsErrorMessage('Ensure this value has at least 5 characters'),
        ),
      );

      expect(
        () => f.validate('abc'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );

      expect(f.toDart('12345'), equals('12345'));
      expect(f.toDart('1234567890'), equals('1234567890'));

      expect(
        () => f.validate('12345678901'),
        throwsA(
          containsErrorMessage('Ensure this value has at most 10 characters'),
        ),
      );

      expect(
        () => f.validate('12345a'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );
    });

    test('regex field with unicode characters', () async {
      final f = RegexField(r'^\w+$', unicode: true);
      expect(f.toDart('éèøçÎÎ你好'), equals('éèøçÎÎ你好'));
    });

    test('change regex after initialization', () async {
      final f = RegexField(r'^[a-z]+$');
      f.regex = RegExp(r'^[0-9]+$');

      expect(f.toDart('1234'), equals('1234'));
      expect(
        () => f.validate('abcd'),
        throwsA(containsErrorMessage('Enter a valid value')),
      );
    });

    test('regex field with stripValue=true', () async {
      final f = RegexField(r'^[a-z]+$', stripValue: true);
      expect(f.toDart(' a'), equals('a'));
      expect(f.toDart('a '), equals('a'));
    });

    test('empty value handling', () async {
      final f = RegexField('', required: false);
      expect(f.toDart(''), isNull);
      expect(f.toDart(null), isNull);

      final f2 = RegexField('', required: false, emptyValue: true);
      expect(f2.toDart(''), equals(''));
      expect(f2.toDart(null), equals(''));
    });
  });
}
