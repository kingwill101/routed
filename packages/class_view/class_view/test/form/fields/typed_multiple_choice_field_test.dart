import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('TypedMultipleChoiceField', () {
    test('coerces single value to int correctly', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
      );

      expect(field.toDart(['1']), equals([1]));
      expect(() => field.toDart(['2']), throwsA(isA<ValidationError>()));
    });

    test('coerces to double correctly', () {
      final field = TypedMultipleChoiceField<double>(
        choices: [
          [1.0, '+1'],
          [-1.0, '-1'],
        ],
        coerce: (val) => double.parse(val.toString()),
      );

      expect(field.toDart(['1']), equals([1.0]));
    });

    test('coerces to bool correctly', () {
      final field = TypedMultipleChoiceField<bool>(
        choices: [
          [true, '+1'],
          [false, '-1'],
        ],
        coerce: (val) => val.toString() == '+1',
      );

      expect(field.toDart(['-1']), equals([false]));
    });

    test('handles multiple values correctly', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
      );

      expect(field.toDart(['1', '-1']), equals([1, -1]));
      expect(() => field.toDart(['1', '2']), throwsA(isA<ValidationError>()));
    });

    test('handles coercion errors appropriately', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          ['A', 'A'],
          ['B', 'B'],
        ],
        coerce: (val) => int.parse(val.toString()),
      );

      expect(() => field.toDart(['B']), throwsA(isA<ValidationError>()));

      // Test required field validation
      expect(() => field.toDart([]), throwsA(isA<ValidationError>()));
    });

    test('handles non-required fields correctly', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        required: false,
      );

      expect(field.toDart([]), equals([]));
    });

    test('handles custom empty value', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
        required: false,
        emptyValue: null,
      );

      expect(field.toDart([]), isNull);
    });

    test('handles special coerce function', () {
      num coerceFunc(dynamic val) {
        return 1 + (num.parse(val.toString()) / 10);
      }

      final field = TypedMultipleChoiceField<num>(
        choices: [
          [1.1, '1'],
          [1.2, '2'],
        ],
        coerce: coerceFunc,
        required: true,
      );

      expect(field.toDart(['2']), equals([1.2]));

      expect(() => field.toDart([]), throwsA(isA<ValidationError>()));

      expect(() => field.toDart(['3']), throwsA(isA<ValidationError>()));
    });

    test('validChoices filters out null values', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          [1, '+1'],
          [null, 'None'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
      );

      expect(
        field.validChoices,
        equals([
          [1, '+1'],
          [-1, '-1'],
        ]),
      );
    });

    test('widget attrs include choices and multiple flag', () {
      final field = TypedMultipleChoiceField<int>(
        choices: [
          [1, '+1'],
          [-1, '-1'],
        ],
        coerce: (val) => int.parse(val.toString()),
      );

      final attrs = field.widgetAttrs(field.widget);
      expect(attrs['choices'], equals('[[1, +1], [-1, -1]]'));
      expect(attrs['multiple'], isTrue);
    });
  });
}
