import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('DateTimeField Tests', () {
    test(
      'clean method handles various input formats',
      () {
        final field = DateTimeField();
        final testCases = [
          {
            'input': DateTime.utc(2006, 10, 25, 14, 30, 59),
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 59),
          },
          {
            'input': DateTime.utc(2006, 10, 25, 14, 30, 59, 200000),
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 59, 0, 200),
          },
          // ISO format strings
          {
            'input': '2006-10-25 14:30:45.000200',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45, 0, 200),
          },
          {
            'input': '2006-10-25 14:30:45.0002',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45, 0, 200),
          },
          {
            'input': '2006-10-25 14:30:45',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45),
          },
          {
            'input': '2006-10-25 14:30:00',
            'expected': DateTime.utc(2006, 10, 25, 14, 30),
          },
          {
            'input': '2006-10-25 14:30',
            'expected': DateTime.utc(2006, 10, 25, 14, 30),
          },
          {'input': '2006-10-25', 'expected': DateTime.utc(2006, 10, 25, 0, 0)},
          // US format strings
          {
            'input': '10/25/2006 14:30:45.000200',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45, 0, 200),
          },
          {
            'input': '10/25/2006 14:30:45',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45),
          },
          {
            'input': '10/25/2006 14:30:00',
            'expected': DateTime.utc(2006, 10, 25, 14, 30),
          },
          {
            'input': '10/25/2006 14:30',
            'expected': DateTime.utc(2006, 10, 25, 14, 30),
          },
          {'input': '10/25/2006', 'expected': DateTime.utc(2006, 10, 25, 0, 0)},
          // Two-digit year format
          {
            'input': '10/25/06 14:30:45.000200',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45, 0, 200),
          },
          {
            'input': '10/25/06 14:30:45',
            'expected': DateTime.utc(2006, 10, 25, 14, 30, 45),
          },
          {
            'input': '10/25/06 14:30:00',
            'expected': DateTime.utc(2006, 10, 25, 14, 30),
          },
          {
            'input': '10/25/06 14:30',
            'expected': DateTime.utc(2006, 10, 25, 14, 30),
          },
          {'input': '10/25/06', 'expected': DateTime.utc(2006, 10, 25, 0, 0)},
          // ISO 8601 formats
          {
            'input': '2014-09-23T22:34:41.614804',
            'expected': DateTime.utc(2014, 9, 23, 22, 34, 41, 0, 614804),
          },
          {
            'input': '2014-09-23T22:34:41',
            'expected': DateTime.utc(2014, 9, 23, 22, 34, 41),
          },
          {
            'input': '2014-09-23T22:34',
            'expected': DateTime.utc(2014, 9, 23, 22, 34),
          },
          {'input': '2014-09-23', 'expected': DateTime.utc(2014, 9, 23, 0, 0)},
          {
            'input': '2014-09-23T22:34Z',
            'expected': DateTime.utc(2014, 9, 23, 22, 34),
          },
          {
            'input': '2014-09-23T22:34+07:00',
            'expected': DateTime.utc(2014, 9, 23, 15, 34), // Adjusted for UTC
          },
          {
            'input': '2006-10-25 14:34:19.000Z',
            'expected': DateTime.utc(2006, 10, 25, 14, 34, 19),
          },
          // Whitespace stripping
        ];

        for (final testCase in testCases) {
          final result = field.toDart(testCase['input']);
          expect(
            result,
            testCase['expected'],
            reason: 'Failed for input: ${testCase['input']}',
          );
        }
      },
      skip:
          'A few uncertainties in the test cases (should revisit how date parsing is done i suppose)',
    );

    test(
      'clean method handles invalid inputs',
      () {
        final field = DateTimeField();
        final invalidInputs = [
          'hello',
          '2006-10-25 4:30 p.m.',
          '2014-09-23T28:23', // Invalid hour
          '2014-13-23', // Invalid month
          '2014-09-32', // Invalid day
          '2014-09-23T22:60', // Invalid minute
          '2014-09-23T22:34:61', // Invalid second
        ];

        for (final input in invalidInputs) {
          expect(
            () => field.toDart(input),
            throwsA(isA<ValidationError>()),
            reason: 'Should throw ValidationError for input: $input',
          );
        }

        // Test empty string with required field
        expect(
          () => field.toDart('   '),
          throwsA(isA<ValidationError>()),
          reason: 'Should throw ValidationError for empty string when required',
        );
      },
      skip:
          'A few uncertainties in the test cases (should revisit how date parsing is done i suppose)',
    );

    test('rejects 12-hour time formats', () {
      final field = DateTimeField();
      final twelveHourFormats = [
        '2006-10-25 4:30 PM',
        '2006-10-25 4:30 AM',
        '2006-10-25 4:30 p.m.',
        '2006-10-25 4:30 a.m.',
        '10/25/2006 4:30 PM',
        '10/25/2006 4:30 AM',
        '10/25/06 4:30 pm',
        '10/25/06 4:30 am',
        '2006-10-25T04:30 PM',
        '2006-10-25T04:30 AM',
        // Test with various spacings
        '2006-10-25 4:30PM',
        '2006-10-25 4:30AM',
        '2006-10-25 4:30p.m.',
        '2006-10-25 4:30a.m.',
      ];

      for (final input in twelveHourFormats) {
        expect(
          () => field.toDart(input),
          throwsA(isA<ValidationError>()),
          reason: 'Should reject 12-hour format: $input',
        );
      }
    });

    test('clean method with custom input formats', () {
      final field = DateTimeField(inputFormats: ['yyyy-MM-dd HH:mm']);

      // Test valid input with custom format
      expect(
        field.toDart('2006-10-25 14:30'),
        DateTime.utc(2006, 10, 25, 14, 30),
      );

      // Test that default formats are not accepted when custom formats are provided
      expect(
        () => field.toDart('2006-10-25 14:30:45'),
        throwsA(isA<ValidationError>()),
        reason:
            'Should not accept default formats when custom formats are provided',
      );

      // Test invalid format for custom format
      expect(
        () => field.toDart('2006/10/25 14:30'),
        throwsA(isA<ValidationError>()),
        reason:
            'Should not accept invalid format when custom formats are provided',
      );
    });

    test('not required field', () {
      final field = DateTimeField(required: false);

      expect(field.toDart(null), null);
      expect(field.toDart(''), null);
    });

    test('has changed method', () {
      final field = DateTimeField();
      final datetime = DateTime.utc(2006, 9, 17, 14, 30);

      expect(field.hasChanged(datetime, '2006-09-17 14:30'), false);

      expect(field.hasChanged(datetime, '2006-09-17 14:31'), true);
    });
  });
}
