import 'package:class_view/class_view.dart';
import 'package:decimal/decimal.dart';
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

void main() {
  group('DecimalFieldTests', () {
    test('basic decimal field', () {
      final f = DecimalField(maxDigits: 4, maxDecimalPlaces: 2);

      // Test required validation
      expect(() => f.validate(null), throwsA(isA<ValidationError>()));

      // Test valid values
      expect(f.toDart('1'), equals(Decimal.parse('1')));
      expect(f.toDart('23'), equals(Decimal.parse('23')));
      expect(f.toDart('3.14'), equals(Decimal.parse('3.14')));
      expect(f.toDart('3.14'), equals(Decimal.parse('3.14')));
      expect(f.toDart(Decimal.parse('3.14')), equals(Decimal.parse('3.14')));
      expect(f.toDart('1.0 '), equals(Decimal.parse('1.0')));
      expect(f.toDart(' 1.0'), equals(Decimal.parse('1.0')));
      expect(f.toDart(' 1.0 '), equals(Decimal.parse('1.0')));

      // Test validation errors
      expect(f.toDart('-12.34'), equals(Decimal.parse('-12.34')));
      expect(f.toDart('-.12'), equals(Decimal.parse('-0.12')));
      expect(f.toDart('-00.12'), equals(Decimal.parse('-0.12')));
      expect(f.toDart('-000.12'), equals(Decimal.parse('-0.12')));
    });

    test('enter a number error', () {
      final f = DecimalField(
        maxValue: Decimal.parse('1'),
        maxDigits: 4,
        maxDecimalPlaces: 2,
      );
      final values = [
        '-NaN',
        'NaN',
        '+NaN',
        '-sNaN',
        'sNaN',
        '+sNaN',
        '-Inf',
        'Inf',
        '+Inf',
        '-Infinity',
        'Infinity',
        '+Infinity',
        'a',
        'łąść',
        '1.0a',
        '--0.12',
      ];

      for (var value in values) {
        expect(
          () => f.toDart(value),
          throwsA(containsErrorMessage('value must be a decimal number')),
          reason: 'Failed for value: $value',
        );
      }
    });

    test('optional decimal field', () {
      final f = DecimalField(
        maxDigits: 4,
        maxDecimalPlaces: 2,
        required: false,
      );
      expect(f.toDart(''), isNull);
      expect(f.toDart(null), isNull);
      expect(f.toDart('1'), equals(Decimal.parse('1')));
    });

    test('decimal field with min/max values', () {
      final f = DecimalField(
        maxDigits: 4,
        maxDecimalPlaces: 2,
        maxValue: Decimal.parse('1.5'),
        minValue: Decimal.parse('0.5'),
      );

      expect(
        () => f.validate(Decimal.parse('1.6')),
        throwsA(
          containsErrorMessage(
            'Ensure this value is less than or equal to 1.5',
          ),
        ),
      );

      expect(
        () => f.validate(Decimal.parse('0.4')),
        throwsA(
          containsErrorMessage(
            'Ensure this value is greater than or equal to 0.5',
          ),
        ),
      );

      expect(f.toDart('1.5'), equals(Decimal.parse('1.5')));
      expect(f.toDart('0.5'), equals(Decimal.parse('0.5')));
      expect(f.toDart('.5'), equals(Decimal.parse('0.5')));
      expect(f.toDart('00.50'), equals(Decimal.parse('0.50')));
    });

    // Debug test to help diagnose issues with decimal places validation
    test('debug decimal places error message', () {
      final f = DecimalField(maxDecimalPlaces: 2);

      try {
        f.toDart('0.00000001');
        fail('Expected ValidationError');
      } catch (e) {
        print('Debug - Error for too many decimal places: $e');
      }
    });

    test('decimal field decimal places validation', () {
      final f = DecimalField(maxDecimalPlaces: 2);

      // Test valid value
      expect(f.toDart('1.23'), equals(Decimal.parse('1.23')));

      // Test invalid value with more decimal places
      try {
        f.toDart('0.00000001');
        fail('Expected ValidationError');
      } catch (e) {
        expect(e, isA<ValidationError>());
        expect(e.toString(), contains('decimal places'));
      }
    });

    test('decimal field max digits validation', () {
      final f = DecimalField(maxDigits: 3);
      // Leading whole zeros "collapse" to one digit
      expect(f.toDart('0000000.10'), equals(Decimal.parse('0.10')));
      // But a leading 0 before the . doesn't count toward max_digits
      expect(f.toDart('0000000.100'), equals(Decimal.parse('0.100')));
      // Only leading whole zeros "collapse" to one digit
      expect(f.toDart('000000.02'), equals(Decimal.parse('0.02')));

      expect(f.toDart('.002'), equals(Decimal.parse('0.002')));
    });

    test('decimal field with max digits and decimal places', () {
      final f = DecimalField(maxDigits: 2, maxDecimalPlaces: 2);
      expect(f.toDart('.01'), equals(Decimal.parse('0.01')));
    });

    test('decimal field scientific notation', () {
      final f = DecimalField(maxDigits: 4, maxDecimalPlaces: 2);

      // 1E+3 = 1000 (4 digits) should be accepted since maxDigits is 4
      expect(f.toDart('1E+3'), equals(Decimal.parse('1000')));

      expect(f.toDart('1E+1'), equals(Decimal.parse('10')));
      expect(f.toDart('1E-1'), equals(Decimal.parse('0.1')));
      expect(f.toDart('0.546e+2'), equals(Decimal.parse('54.6')));
    });
  });
}
