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
  group('DurationField', () {
    test('clean valid durations', () {
      final field = DurationField<Duration>();

      expect(field.toDart('00:00:30'), equals(const Duration(seconds: 30)));
      expect(
        field.toDart('00:15:30'),
        equals(const Duration(minutes: 15, seconds: 30)),
      );
      expect(
        field.toDart('01:15:30'),
        equals(const Duration(hours: 1, minutes: 15, seconds: 30)),
      );
      expect(field.toDart('25:00:00'), equals(const Duration(hours: 25)));
    });

    test('clean invalid durations throws ValidationError', () {
      final field = DurationField<Duration>();

      expect(
        () => field.toDart(''),
        throwsA(containsErrorMessage('This field is required')),
      );

      expect(
        () => field.toDart('not_a_time'),
        throwsA(containsErrorMessage('Enter a valid duration')),
      );

      expect(
        () => field.toDart('00:60:00'),
        throwsA(containsErrorMessage('Enter a valid duration')),
      );

      expect(
        () => field.toDart('00:00:60'),
        throwsA(containsErrorMessage('Enter a valid duration')),
      );
    });

    test('clean not required field', () {
      final field = DurationField<Duration>(required: false);
      expect(field.toDart(''), isNull);
    });

    test('validate min duration', () {
      final field = DurationField<Duration>(
        minDuration: const Duration(hours: 1),
      );

      expect(
        () => field.validate(const Duration(minutes: 30)),
        throwsA(containsErrorMessage('Duration must be 01:00:00 or longer')),
      );
    });

    test('validate max duration', () {
      final field = DurationField<Duration>(
        maxDuration: const Duration(hours: 2),
      );

      expect(
        () => field.validate(const Duration(hours: 3)),
        throwsA(containsErrorMessage('Duration must be 02:00:00 or shorter')),
      );
    });

    test('format duration correctly', () {
      final field = DurationField<Duration>();

      final duration = const Duration(hours: 1, minutes: 15, seconds: 30);
      expect(field.toDart('01:15:30'), equals(duration));

      // Test that the formatted string matches what we expect
      expect(field.formatDuration(duration), equals('01:15:30'));
    });
  });
}
