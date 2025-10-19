import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('IntegerField Tests', () {
    late IntegerField field;

    setUp(() {
      field = IntegerField();
    });

    test('validates required field', () async {
      // Required by default
      await expectLater(() => field.clean(''), throwsA(isA<ValidationError>()));

      await expectLater(
        () => field.clean(null),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates integer values', () async {
      // Valid integers
      expect(await field.clean('1'), equals(1));
      expect(await field.clean('23'), equals(23));
      expect(await field.clean(42), equals(42));

      // Whitespace handling
      expect(await field.clean('1 '), equals(1));
      expect(await field.clean(' 1'), equals(1));
      expect(await field.clean(' 1 '), equals(1));

      // Invalid values
      await expectLater(
        () => field.clean('a'),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(
        () => field.clean('1a'),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(
        () => field.clean(3.14),
        throwsA(isA<ValidationError>()),
      );
    });

    test('handles optional field correctly', () async {
      field = IntegerField(required: false);

      // Empty values should return null
      expect(await field.clean(''), isNull);
      expect(await field.clean(null), isNull);

      // Valid integers still work
      expect(await field.clean('1'), equals(1));
      expect(await field.clean('23'), equals(23));

      // Invalid values still throw
      await expectLater(
        () => field.clean('a'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates maximum value constraint', () async {
      field = IntegerField(maxValue: 10);

      // Valid values
      expect(await field.clean('1'), equals(1));
      expect(await field.clean('10'), equals(10));

      // Invalid values
      await expectLater(
        () => field.clean('11'),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(() => field.clean(11), throwsA(isA<ValidationError>()));
    });

    test('validates minimum value constraint', () async {
      field = IntegerField(minValue: 10);

      // Valid values
      expect(await field.clean('10'), equals(10));
      expect(await field.clean('11'), equals(11));

      // Invalid values
      await expectLater(
        () => field.clean('9'),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(() => field.clean(9), throwsA(isA<ValidationError>()));
    });

    test('validates min and max value constraints together', () async {
      field = IntegerField(minValue: 10, maxValue: 20);

      // Valid values
      expect(await field.clean('10'), equals(10));
      expect(await field.clean('15'), equals(15));
      expect(await field.clean('20'), equals(20));

      // Invalid values - too low
      await expectLater(
        () => field.clean('9'),
        throwsA(isA<ValidationError>()),
      );

      // Invalid values - too high
      await expectLater(
        () => field.clean('21'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates step size constraint', () async {
      field = IntegerField(stepSize: 3);

      // Valid values (multiples of 3)
      expect(await field.clean('0'), equals(0));
      expect(await field.clean('3'), equals(3));
      expect(await field.clean('6'), equals(6));
      expect(await field.clean('12'), equals(12));

      // Invalid values (not multiples of 3)
      await expectLater(
        () => field.clean('1'),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(
        () => field.clean('4'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates step size with offset', () async {
      field = IntegerField(stepSize: 3, minValue: -1);

      // Valid values (following pattern: -1, 2, 5, 8, ...)
      expect(await field.clean('-1'), equals(-1));
      expect(await field.clean('2'), equals(2));
      expect(await field.clean('5'), equals(5));

      // Invalid values
      await expectLater(
        () => field.clean('0'),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(
        () => field.clean('1'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('handles floating point input', () async {
      // Integer-like floats should be accepted
      expect(await field.clean('1.0'), equals(1));
      expect(await field.clean('1.'), equals(1));
      expect(await field.clean(' 1.0 '), equals(1));

      // Non-integer floats should be rejected
      await expectLater(
        () => field.clean('1.5'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('handles large numbers', () async {
      // Test with a large integer value
      final largeNum = 9223372036854775807; // max int64
      expect(await field.clean(largeNum.toString()), equals(largeNum));
    });
  });
}
