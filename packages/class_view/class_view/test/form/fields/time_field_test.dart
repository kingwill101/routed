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
  group('TimeField Tests', () {
    test('basic time validation', () {
      final field = TimeField<DateTime>();

      // Test valid time object input
      final time1 = DateTime(1970, 1, 1, 14, 25);
      expect(field.toDart('14:25'), time1);

      // Test time with seconds
      final time2 = DateTime(1970, 1, 1, 14, 25, 59);
      expect(field.toDart('14:25:59'), time2);

      // Test invalid string input
      expect(
        () => field.toDart('hello'),
        throwsA(containsErrorMessage('Enter a valid time')),
      );

      // Test invalid format
      expect(
        () => field.toDart('1:24 p.m.'),
        throwsA(containsErrorMessage('Enter a valid time')),
      );
    });

    test('custom input formats', () {
      final field = TimeField<DateTime>(inputFormats: ['h:mm a', 'HH:mm']);

      // Test AM/PM format
      final time1 = DateTime(1970, 1, 1, 4, 25);
      expect(field.toDart('4:25 AM'), time1);

      final time2 = DateTime(1970, 1, 1, 16, 25);
      expect(field.toDart('4:25 PM'), time2);

      // Test 24-hour format
      final time3 = DateTime(1970, 1, 1, 14, 30);
      expect(field.toDart('14:30'), time3);

      // Test invalid format for configured formats
      expect(
        () => field.toDart('14:30:45'),
        throwsA(containsErrorMessage('Enter a valid time')),
      );
    });

    test('whitespace handling', () {
      final field = TimeField<DateTime>();

      // Test whitespace stripping
      final time1 = DateTime(1970, 1, 1, 14, 25);
      expect(field.toDart(' 14:25 '), time1);

      final time2 = DateTime(1970, 1, 1, 14, 25, 59);
      expect(field.toDart(' 14:25:59 '), time2);

      // Test empty string
      expect(field.toDart('   '), null);
    });

    test('min/max time validation', () async {
      final minTime = DateTime(1970, 1, 1, 9, 0);
      final maxTime = DateTime(1970, 1, 1, 17, 0);

      final field = TimeField<DateTime>(minTime: minTime, maxTime: maxTime);

      // Test valid time within range
      await field.validate(DateTime(1970, 1, 1, 12, 0));

      // Test time before min
      expect(
        () => field.validate(DateTime(1970, 1, 1, 8, 0)),
        throwsA(containsErrorMessage('Time must be 09:00:00 or later')),
      );

      // Test time after max
      expect(
        () => field.validate(DateTime(1970, 1, 1, 18, 0)),
        throwsA(containsErrorMessage('Time must be 17:00:00 or earlier')),
      );
    });

    test('widget attributes', () {
      final minTime = DateTime(1970, 1, 1, 9, 0);
      final maxTime = DateTime(1970, 1, 1, 17, 0);

      final field = TimeField<DateTime>(minTime: minTime, maxTime: maxTime);

      final attrs = field.widgetAttrs(field.widget);
      expect(attrs['min'], '09:00:00');
      expect(attrs['max'], '17:00:00');
    });

    test('change detection', () {
      final field = TimeField<DateTime>();

      final time1 = DateTime(1970, 1, 1, 14, 25);
      final time2 = DateTime(1970, 1, 1, 14, 25, 30);
      final time3 = DateTime(1970, 1, 1, 15, 25);

      // Same times should not be considered changed
      expect(field.hasChanged(time1, time1), false);

      // Different seconds should be considered changed
      expect(field.hasChanged(time1, time2), true);

      // Different hours should be considered changed
      expect(field.hasChanged(time1, time3), true);

      // Null handling
      expect(field.hasChanged(null, null), false);
      expect(field.hasChanged(time1, null), true);
      expect(field.hasChanged(null, time1), true);
    });
  });
}
