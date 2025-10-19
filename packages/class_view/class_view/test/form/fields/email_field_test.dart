import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

class TestDomainValidator extends Validator<String> {
  @override
  Future<void> validate(String? value) async {
    if (value != null && value.endsWith('@test.com')) {
      throw ValidationError({
        'invalid': ['test.com emails not allowed'],
      });
    }
  }
}

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

void main() {
  group('EmailField Tests', () {
    late EmailField field;

    setUp(() {
      field = EmailField();
    });

    test('empty values return null for optional fields', () async {
      field = EmailField(required: false);
      expect(await field.clean(null), isNull);
      expect(await field.clean(''), isNull);
      expect(await field.clean(' '), isNull);
    });

    test('empty values raise ValidationError for required fields', () async {
      field = EmailField(required: true);

      await expectLater(
        () => field.clean(null),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(() => field.clean(''), throwsA(isA<ValidationError>()));

      await expectLater(
        () => field.clean(' '),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates valid email addresses', () async {
      final validEmails = [
        'email@domain.com',
        'firstname.lastname@domain.com',
        'email@subdomain.domain.com',
        'firstname+lastname@domain.com',
        'email@[123.123.123.123]',
        '"email"@domain.com',
        '1234567890@domain.com',
        'email@domain-one.com',
        '_______@domain.com',
        'email@domain.name',
        'email@domain.co.jp',
        'firstname-lastname@domain.com',
      ];

      for (final email in validEmails) {
        expect(await field.clean(email), equals(email.toLowerCase()));
      }
    });

    test('rejects invalid email addresses', () async {
      final invalidEmails = [
        'plainaddress',
        '#@%^%#\$@#\$@#.com',
        '@domain.com',
        'Joe Smith <email@domain.com>',
        'email.domain.com',
        'email@domain@domain.com',
        '.email@domain.com',
        'email.@domain.com',
        'email..email@domain.com',
        'email@domain.com (Joe Smith)',
        'email@domain',
        'email@-domain.com',
        'email@domain..com',
        'email@123.123.123.123',
      ];

      for (final email in invalidEmails) {
        await expectLater(
          () => field.clean(email),
          throwsA(isA<ValidationError>()),
        );
      }
    });

    test('normalizes email addresses', () async {
      // Test case normalization
      expect(await field.clean('email@DOMAIN.com'), equals('email@domain.com'));
      expect(await field.clean('EMAIL@domain.COM'), equals('email@domain.com'));

      // Test whitespace handling
      expect(
        await field.clean(' email@domain.com '),
        equals('email@domain.com'),
      );
      expect(
        await field.clean('\temail@domain.com\n'),
        equals('email@domain.com'),
      );
    });

    test('supports custom error messages', () async {
      field = EmailField(
        errorMessages: {
          'required': 'Custom required error',
          'invalid': 'Custom invalid email error',
        },
      );

      try {
        await field.clean('invalid-email');
        fail('Should have thrown ValidationError');
      } catch (e) {
        // Just check that it contains the custom message somewhere
        expect(
          (e as ValidationError).toString(),
          contains('Custom invalid email error'),
        );
      }
    });

    test('validates max length', () async {
      field = EmailField(maxLength: 20);

      await field.clean('short@domain.com');

      await expectLater(
        () => field.clean('very.long.email@very.long.domain.com'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('handles unicode characters in local part', () async {
      final validUnicodeEmails = [
        'αβγδε@domain.com',
        'θωερτψ@domain.com',
        'čćžš@domain.com',
        'ñándú@domain.com',
      ];

      for (final email in validUnicodeEmails) {
        expect(await field.clean(email), equals(email.toLowerCase()));
      }
    });

    test('handles IDN domains', () async {
      final validIdnEmails = [
        'email@mañana.com',
        'email@domain.рф',
        'email@münchen.de',
        'email@straße.de',
      ];

      for (final email in validIdnEmails) {
        expect(await field.clean(email), equals(email.toLowerCase()));
      }
    });

    test('validates email with custom domain validator', () async {
      field = EmailField(validators: [TestDomainValidator()]);

      await field.clean('email@domain.com');

      await expectLater(
        () => field.clean('email@test.com'),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
