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
  group('ValidationError', () {
    test('toString returns the error message', () {
      final error = ValidationError({
        'invalid': ['Test error'],
      });
      expect(error.toString(), contains('Test error'));
    });
  });

  group('MinLengthValidator', () {
    late MinLengthValidator<String> validator;

    setUp(() {
      validator = MinLengthValidator(3);
    });

    test('accepts values with sufficient length', () async {
      await validator.validate('test');
      await validator.validate('12345');
    });

    test('rejects values that are too short', () async {
      expect(() => validator.validate('ab'), throwsA(isA<ValidationError>()));
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });

  group('MaxLengthValidator', () {
    late MaxLengthValidator<String> validator;

    setUp(() {
      validator = MaxLengthValidator(5);
    });

    test('accepts values within max length', () async {
      await validator.validate('test');
      await validator.validate('12345');
    });

    test('rejects values that are too long', () async {
      expect(
        () => validator.validate('123456'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });

  group('RegexValidator', () {
    late RegexValidator<String> validator;

    setUp(() {
      validator = RegexValidator(RegExp(r'^\d{3}-\d{2}-\d{4}$'));
    });

    test('accepts matching values', () async {
      await validator.validate('123-45-6789');
    });

    test('rejects non-matching values', () async {
      expect(
        () => validator.validate('invalid'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });

  group('MinValueValidator', () {
    late MinValueValidator<int> validator;

    setUp(() {
      validator = MinValueValidator(5);
    });

    test('accepts values above minimum', () async {
      await validator.validate(5);
      await validator.validate(6);
    });

    test('rejects values below minimum', () async {
      expect(() => validator.validate(4), throwsA(isA<ValidationError>()));
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });

  group('MaxValueValidator', () {
    late MaxValueValidator<int> validator;

    setUp(() {
      validator = MaxValueValidator(10);
    });

    test('accepts values below maximum', () async {
      await validator.validate(9);
      await validator.validate(10);
    });

    test('rejects values above maximum', () async {
      expect(() => validator.validate(11), throwsA(isA<ValidationError>()));
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });

  group('EmailValidator', () {
    late EmailValidator<String> validator;

    setUp(() {
      validator = EmailValidator();
    });

    test('accepts valid email addresses', () async {
      await validator.validate('test@example.com');
      await validator.validate('user.name+tag@domain.co.uk');
    });

    test('rejects invalid email addresses', () async {
      expect(
        () => validator.validate('invalid'),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => validator.validate('test@'),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => validator.validate('@domain.com'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });

  group('URLValidator', () {
    late URLValidator<String> validator;

    setUp(() {
      validator = const URLValidator();
    });

    test('accepts valid URLs', () async {
      await validator.validate('https://example.com');
      await validator.validate('http://sub.domain.co.uk/path?query=1');
      await validator.validate('ftp://files.example.com');
    });

    test('rejects invalid URLs', () async {
      expect(
        () => validator.validate('not-a-url'),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => validator.validate('http://'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts null values', () async {
      await validator.validate(null);
    });
  });
}
