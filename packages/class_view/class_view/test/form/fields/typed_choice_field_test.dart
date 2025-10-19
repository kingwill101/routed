import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('TypedChoiceField', () {
    test('coerces to int correctly', () {
      final field = TypedChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: 0,
      );

      expect(field.toDart('1'), equals(1));
      expect(() => field.toDart('2'), throwsA(isA<ValidationError>()));
    });

    test('coerces to double correctly', () {
      final field = TypedChoiceField<double>(
        choices: [
          [1.0, '+1'],
          [-1.0, '-1'],
        ],
        coerce: (val) => double.parse(val.toString()),
        emptyValue: 0.0,
      );

      expect(field.toDart('1'), equals(1.0));
    });

    test('coerces to bool correctly', () {
      final field = TypedChoiceField<bool>(
        choices: [
          [true, '+1'],
          [false, '-1'],
        ],
        coerce: (val) => val.toString() == '+1',
        emptyValue: false,
      );

      expect(field.toDart('+1'), isTrue);
    });

    test('handles coercion errors appropriately', () {
      final field = TypedChoiceField<int>(
        choices: [
          ['A', 'A'],
          ['B', 'B'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: 0,
      );

      expect(() => field.toDart('B'), throwsA(isA<ValidationError>()));

      // Test required field validation
      final requiredField = TypedChoiceField<int>(
        choices: [
          ['A', 'A'],
          ['B', 'B'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: 0,
        required: true,
      );

      expect(() => requiredField.toDart(''), throwsA(isA<ValidationError>()));
    });

    test('handles non-required fields correctly', () {
      final field = TypedChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: 0,
        required: false,
      );

      expect(field.toDart(''), equals(0));
    });

    test('handles custom empty value', () {
      final field = TypedChoiceField<int?>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: null,
        required: false,
      );

      expect(field.toDart(''), isNull);
    });

    test('handles special coerce function', () {
      num coerceFunc(dynamic val) {
        return 1 + (num.parse(val.toString()) / 10);
      }

      final field = TypedChoiceField<num>(
        choices: [
          [1.1, '1'],
          [1.2, '2'],
        ],
        coerce: coerceFunc,
        emptyValue: 0,
        required: true,
      );

      expect(field.toDart('2'), equals(1.2));

      expect(() => field.toDart(''), throwsA(isA<ValidationError>()));

      expect(() => field.toDart('3'), throwsA(isA<ValidationError>()));
    });

    test('validChoices filters out null values', () {
      final field = TypedChoiceField<int?>(
        choices: [
          [1, '+1'],
          [null, 'None'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: null,
      );

      expect(
        field.validChoices,
        equals([
          [1, '+1'],
          [-1, '-1'],
        ]),
      );
    });

    test('widget attrs include choices for Select widget', () {
      final field = TypedChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        emptyValue: 0,
      );

      final attrs = field.widgetAttrs(field.widget);
      expect(attrs['choices'], equals('[[1, +1], [-1, -1]]'));
    });
  });
}
