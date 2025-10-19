import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('CharField Tests', () {
    late CharField field;

    setUp(() {
      field = CharField();
    });

    test(
      'empty values are converted to empty strings when emptyValue is true',
      () async {
        field = CharField(required: false, emptyValue: true);
        expect(await field.clean(null), equals(''));
        expect(await field.clean(''), equals(''));
        expect(await field.clean(' '), equals(''));
      },
    );

    test('empty values raise ValidationError for required fields', () async {
      field = CharField(required: true);

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

    test('strips whitespace when stripValue is true', () async {
      field = CharField(stripValue: true);
      expect(await field.clean(' hello '), equals('hello'));
      expect(await field.clean('\thello\n'), equals('hello'));
    });

    test('does not strip whitespace when stripValue is false', () async {
      field = CharField(stripValue: false);
      expect(await field.clean(' hello '), equals(' hello '));
      expect(await field.clean('\thello\n'), equals('\thello\n'));
    });

    test('validates max length', () async {
      field = CharField(maxLength: 5);

      await field.clean('hello');

      await expectLater(
        () => field.clean('hello world'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates min length', () async {
      field = CharField(minLength: 3);

      await field.clean('hello');

      await expectLater(
        () => field.clean('hi'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('validates against empty strings when required', () async {
      field = CharField(required: true);

      await expectLater(() => field.clean(''), throwsA(isA<ValidationError>()));
    });

    test('accepts valid strings', () async {
      field = CharField();
      expect(await field.clean('hello'), equals('hello'));
      expect(await field.clean('hello world'), equals('hello world'));
      expect(await field.clean('12345'), equals('12345'));
    });

    test('handles non-string inputs', () async {
      field = CharField();
      expect(await field.clean(123), equals('123'));
      expect(await field.clean(true), equals('true'));
      expect(await field.clean(3.14), equals('3.14'));
    });

    test('adds maxlength and minlength attributes to widget', () {
      field = CharField(maxLength: 10, minLength: 2);
      final attrs = field.widgetAttrs(field.widget);
      expect(attrs['maxlength'], equals('10'));
      expect(attrs['minlength'], equals('2'));
    });

    // Features implemented from Django

    group('Django Features', () {
      test('normalizes line endings', () async {
        field = CharField(normalizeLineEndings: true);
        expect(await field.clean('hello\r\nworld'), equals('hello\nworld'));
        expect(await field.clean('hello\rworld'), equals('hello\nworld'));
        expect(await field.clean('hello\nworld'), equals('hello\nworld'));
      });

      test('supports custom empty values', () async {
        field = CharField(
          required: false,
          emptyValue: true,
          emptyValues: [null, '', [], {}, 'EMPTY'],
        );

        expect(await field.clean(null), equals(''));
        expect(await field.clean([]), equals(''));
        expect(await field.clean({}), equals(''));
        expect(await field.clean('EMPTY'), equals(''));
      });

      test('supports custom error messages', () async {
        field = CharField(
          maxLength: 5,
          errorMessages: {
            'max_length': 'Custom max length error',
            'min_length': 'Custom min length error',
            'required': 'Custom required error',
          },
        );

        try {
          await field.clean('too long string');
          fail('Should have thrown ValidationError');
        } catch (e) {
          expect(
            (e as ValidationError).errors['max_length']![0],
            equals('Custom max length error'),
          );
        }
      });

      test('handles null characters', () async {
        field = CharField();
        await expectLater(
          () => field.clean('hello\x00world'),
          throwsA(isA<ValidationError>()),
        );
      });

      test('renders correctly', () async {
        field = CharField();
        expect(field.toString(), contains('CharField'));
      });
    });
  });
}
