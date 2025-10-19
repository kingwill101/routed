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
  test('basic float field validation', () {
    final f = FloatField();

    // Test required validation
    expect(
      () => f.toDart(''),
      throwsA(containsErrorMessage('This field is required')),
    );

    expect(
      () => f.toDart(null),
      throwsA(containsErrorMessage('This field is required')),
    );

    // Test valid values
    expect(f.toDart('1'), equals(1.0));
    expect(f.toDart('1') is double, isTrue);
    expect(f.toDart('23'), equals(23.0));
    expect(f.toDart('3.14'), equals(3.14));
    expect(f.toDart(3.14), equals(3.14));
    expect(f.toDart(42), equals(42.0));

    // Test invalid values
    expect(
      () => f.toDart('a'),
      throwsA(containsErrorMessage('Enter a number')),
    );

    // Test whitespace handling
    expect(f.toDart('1.0 '), equals(1.0));
    expect(f.toDart(' 1.0'), equals(1.0));
    expect(f.toDart(' 1.0 '), equals(1.0));

    // Test invalid number format
    expect(
      () => f.toDart('1.0a'),
      throwsA(containsErrorMessage('Enter a number')),
    );

    // Test special values
    expect(
      () => f.toDart('Infinity'),
      throwsA(containsErrorMessage('Enter a number')),
    );

    expect(
      () => f.toDart('NaN'),
      throwsA(containsErrorMessage('Enter a number')),
    );

    expect(
      () => f.toDart('-Inf'),
      throwsA(containsErrorMessage('Enter a number')),
    );
  });

  test('optional float field', () {
    final f = FloatField(required: false);

    expect(f.toDart(''), isNull);
    expect(f.toDart(null), isNull);
    expect(f.toDart('1'), equals(1.0));
  });

  test('float field with min and max values', () {
    final f = FloatField(maxValue: 1.5, minValue: 0.5);

    expect(
      () => f.toDart('1.6'),
      throwsA(
        containsErrorMessage('Ensure this value is less than or equal to 1.5'),
      ),
    );

    expect(
      () => f.toDart('0.4'),
      throwsA(
        containsErrorMessage(
          'Ensure this value is greater than or equal to 0.5',
        ),
      ),
    );

    expect(f.toDart('1.5'), equals(1.5));
    expect(f.toDart('0.5'), equals(0.5));
  });

  test('float field with step size', () {
    final f = FloatField(stepSize: 0.02);

    expect(
      () => f.toDart('0.01'),
      throwsA(
        containsErrorMessage(
          'Ensure this value is a multiple of step size 0.02',
        ),
      ),
    );

    expect(f.toDart('2.34'), equals(2.34));
    expect(f.toDart('2.1'), equals(2.1));
    expect(f.toDart('-.5'), equals(-0.5));
    expect(f.toDart('-1.26'), equals(-1.26));
  });

  test('float field with step size and min value', () {
    final f = FloatField(stepSize: 0.02, minValue: 0.01);

    expect(
      () => f.toDart('0.02'),
      throwsA(
        containsErrorMessage(
          'Ensure this value is a multiple of step size 0.02, starting from 0.01, '
          'e.g. 0.01, 0.03, 0.05, and so on',
        ),
      ),
    );

    expect(f.toDart('2.33'), equals(2.33));
    expect(f.toDart('0.11'), equals(0.11));
  });

  test('float field widget attributes', () {
    final f = FloatField(
      widget: NumberInput(
        attrs: {
          'step': 0.01.toString(),
          'max': 1.0.toString(),
          'min': 0.0.toString(),
        },
      ),
    );

    expect(f.widget, isNotNull);
    expect(f.widget, isA<NumberInput>());
    expect(
      double.parse((f.widget as NumberInput).attrs['step'] as String),
      equals(0.01),
    );
    expect(
      double.parse((f.widget as NumberInput).attrs['max'] as String),
      equals(1.0),
    );
    expect(
      double.parse((f.widget as NumberInput).attrs['min'] as String),
      equals(0.0),
    );
  });

  test('float field value changed detection', () {
    final f = FloatField();
    const n = 4.35;

    expect(f.hasChanged(n, double.parse('4.3500')), isFalse);
  });
}
