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
  group('ComboField Tests', () {
    test('test_combofield_1', () async {
      final field = ComboField(
        fields: [CharField(maxLength: 20), EmailField()],
      );

      expect(await field.clean("test@example.com"), equals("test@example.com"));

      await expectLater(
        () => field.clean("longemailaddress@example.com"),
        throwsA(
          containsErrorMessage('Ensure this value has at most 20 characters'),
        ),
      );

      await expectLater(
        () => field.clean("not an email"),
        throwsA(containsErrorMessage('Enter a valid email address')),
      );

      await expectLater(
        () => field.clean(""),
        throwsA(containsErrorMessage('This field is required')),
      );

      await expectLater(
        () => field.clean(null),
        throwsA(containsErrorMessage('This field is required')),
      );
    });

    test('test_combofield_2', () async {
      final field = ComboField(
        fields: [CharField(maxLength: 20), EmailField()],
        required: false,
      );

      expect(await field.clean("test@example.com"), equals("test@example.com"));

      await expectLater(
        () => field.clean("longemailaddress@example.com"),
        throwsA(
          containsErrorMessage('Ensure this value has at most 20 characters'),
        ),
      );

      await expectLater(
        () => field.clean("not an email"),
        throwsA(containsErrorMessage('Enter a valid email address')),
      );

      expect(await field.clean(""), equals(""));
      expect(await field.clean(null), equals(""));
    });
  });
}
