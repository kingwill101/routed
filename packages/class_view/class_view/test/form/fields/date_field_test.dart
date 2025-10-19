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
  group('DateField Tests', () {
    late DateField field;

    setUp(() {
      field = DateField();
    });

    // Debug test to see the actual error messages
    test('debug error messages', () async {
      try {
        await field.clean('invalid-date');
        fail('Should have thrown ValidationError');
      } catch (e) {
        print('Debug - Error for invalid date: $e');
      }

      try {
        await field.clean('');
        fail('Should have thrown ValidationError');
      } catch (e) {
        print('Debug - Error for empty string: $e');
      }

      try {
        await field.clean('2006-2-31');
        print('Debug - 2006-2-31 parsed as: ${await field.clean('2006-2-31')}');
      } catch (e) {
        print('Debug - Error for 2006-2-31: $e');
      }

      try {
        await field.clean('25/10/06');
        print('Debug - 25/10/06 parsed as: ${await field.clean('25/10/06')}');
      } catch (e) {
        print('Debug - Error for 25/10/06: $e');
      }

      try {
        await field.clean(' October  25 2006 ');
        print(
          'Debug - " October  25 2006 " parsed as: ${await field.clean(' October  25 2006 ')}',
        );
      } catch (e) {
        print('Debug - Error for " October  25 2006 ": $e');
      }
    });

    test('form field validation', () async {
      // Test DateTime input
      final dateTime = DateTime(2006, 10, 25, 14, 30);
      expect(await field.clean(dateTime), equals(DateTime.utc(2006, 10, 25)));

      // Test string input with default formats
      expect(
        await field.clean('2006-10-25'),
        equals(DateTime.utc(2006, 10, 25)),
      );
      expect(
        await field.clean('10/25/2006'),
        equals(DateTime.utc(2006, 10, 25)),
      );
      expect(await field.clean('10/25/06'), equals(DateTime.utc(2006, 10, 25)));
      expect(
        await field.clean('Oct 25 2006'),
        equals(DateTime.utc(2006, 10, 25)),
      );
      expect(
        await field.clean('October 25 2006'),
        equals(DateTime.utc(2006, 10, 25)),
      );
      expect(
        await field.clean('October 25, 2006'),
        equals(DateTime.utc(2006, 10, 25)),
      );
      expect(
        await field.clean('25 October 2006'),
        equals(DateTime.utc(2006, 10, 25)),
      );

      // Test clearly invalid formats - these should definitely fail
      await expectLater(
        () => field.clean('I am not a date'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );

      await expectLater(
        () => field.clean('200a-10-25'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );

      // Test dates with invalid month values (25 is not a valid month)
      await expectLater(
        () => field.clean('25/10/06'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );
    });

    test('empty values', () async {
      // Required field (default)
      await expectLater(
        () => field.clean(null),
        throwsA(containsErrorMessage('This field is required')),
      );

      await expectLater(
        () => field.clean(''),
        throwsA(containsErrorMessage('This field is required')),
      );

      await expectLater(
        () => field.clean(' '),
        throwsA(containsErrorMessage('This field is required')),
      );

      // Optional field
      field = DateField(required: false);
      expect(await field.clean(null), isNull);
      expect(await field.clean(''), isNull);
      expect(await field.clean(' '), isNull);
    });

    test('custom input formats', () async {
      field = DateField(inputFormats: ['yyyy MM dd']);

      // Should work with the custom format
      expect(
        await field.clean('2006 10 25'),
        equals(DateTime.utc(2006, 10, 25)),
      );

      // Should fail with default formats
      await expectLater(
        () => field.clean('2006-10-25'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );

      await expectLater(
        () => field.clean('10/25/2006'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );
    });

    test('handles whitespace', () {
      field = DateField();
      expect(field.toDart('10/25/2006'), equals(DateTime.utc(2006, 10, 25)));
      expect(field.toDart(' 10/25/2006 '), equals(DateTime.utc(2006, 10, 25)));
      expect(field.toDart('10/25/06'), equals(DateTime.utc(2006, 10, 25)));
      expect(field.toDart(' 10/25/06 '), equals(DateTime.utc(2006, 10, 25)));

      // Optional field and empty strings
      field = DateField(required: false);
      expect(field.toDart('   '), isNull);
    });

    test('custom error messages', () async {
      field = DateField(
        errorMessages: {
          'required': 'Custom required error',
          'invalid': 'Custom invalid date error',
        },
      );

      // Test required error
      try {
        await field.clean(null);
        fail('Should have thrown ValidationError');
      } catch (e) {
        expect(
          (e as ValidationError).toString(),
          contains('Custom required error'),
        );
      }

      // Test invalid date error
      try {
        await field.clean('invalid-date');
        fail('Should have thrown ValidationError');
      } catch (e) {
        expect(
          (e as ValidationError).toString(),
          contains('Custom invalid date error'),
        );
      }
    });

    test('value changes detection', () async {
      final initialDate = DateTime.utc(2008, 4, 1);

      // No change
      expect(field.hasChanged(initialDate, '2008-04-01'), isFalse);

      // Changed
      expect(field.hasChanged(initialDate, '2008-04-02'), isTrue);

      // Different format but same date
      expect(field.hasChanged(initialDate, 'April 1, 2008'), isFalse);

      // Time component should be ignored
      expect(
        field.hasChanged(DateTime(2008, 4, 1, 12, 30), '2008-04-01'),
        isFalse,
      );
    });

    test('two digit years', () async {
      // Years 00-69 should be mapped to 2000-2069
      expect(await field.clean('10/25/00'), equals(DateTime.utc(2000, 10, 25)));
      expect(await field.clean('10/25/68'), equals(DateTime.utc(2068, 10, 25)));

      // Years 70-99 should be mapped to 1970-1999
      expect(await field.clean('10/25/70'), equals(DateTime.utc(1970, 10, 25)));
      expect(await field.clean('10/25/99'), equals(DateTime.utc(1999, 10, 25)));
    });
  });
}
