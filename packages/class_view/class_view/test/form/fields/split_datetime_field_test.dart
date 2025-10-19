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
  group('SplitDateTimeField Tests', () {
    late DateField dateField;
    late TimeField<DateTime> timeField;
    late SplitDateTimeField<DateTime> field;

    setUp(() {
      dateField = DateField();
      timeField = TimeField<DateTime>();
      field = SplitDateTimeField<DateTime>(
        dateField: dateField,
        timeField: timeField,
        widget: SplitDateTimeWidget(),
      );
    });

    // Debug test to diagnose issue
    test('debug error messages', () {
      try {
        field.toDart('hello');
        fail('Expected ValidationError');
      } catch (e) {
        print('Debug - Error for invalid date: $e');
      }

      try {
        field.toDart('2006-01-10 invalid');
        fail('Expected ValidationError');
      } catch (e) {
        print('Debug - Error for invalid time: $e');
      }
    });

    test('basic field functionality', () async {
      expect(field.widget, isA<SplitDateTimeWidget>());

      // Test valid input
      final result = field.toDart('2006-01-10 07:30');
      expect(result, DateTime(2006, 1, 10, 7, 30));

      // Test invalid input
      expect(
        () => field.toDart('hello'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );

      // Test invalid date and time
      expect(
        () => field.toDart('hello there'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );

      // Test invalid time
      expect(
        () => field.toDart('2006-01-10 there'),
        throwsA(containsErrorMessage('Enter a valid time')),
      );

      // Test invalid date
      expect(
        () => field.toDart('hello 07:30'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );
    });

    test('non-required field functionality', () async {
      field = SplitDateTimeField<DateTime>(
        dateField: dateField,
        timeField: timeField,
        required: false,
        widget: SplitDateTimeWidget(),
      );

      // Test valid input
      final result = field.toDart('2006-01-10 07:30');
      expect(result, DateTime(2006, 1, 10, 7, 30));

      // Test empty inputs
      expect(field.toDart(null), isNull);
      expect(field.toDart(''), isNull);

      // Test invalid input
      expect(
        () => field.toDart('hello'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );

      // Test partial inputs
      expect(
        () => field.toDart('2006-01-10'),
        throwsA(containsErrorMessage('Enter a valid date')),
      );
    });

    test('widget configuration', () {
      final widget = SplitDateTimeWidget(
        dateFormat: 'dd/MM/yyyy',
        timeFormat: 'HH:mm:ss',
        dateAttrs: {'class': 'date-input'},
        timeAttrs: {'class': 'time-input'},
      );

      expect(widget.supportsMicroseconds, isFalse);
      expect(widget.widgets.length, equals(2));
    });
  });
}
