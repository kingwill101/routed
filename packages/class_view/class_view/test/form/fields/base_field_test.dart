import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

class TestField<T> extends Field<T> {
  TestField({bool? required, List<Validator<T>>? validators, bool? disabled})
    : super(
        required: required ?? false,
        validators: validators ?? [],
        disabled: disabled ?? false,
      );

  @override
  T? toDart(dynamic value) => value as T?;
}

class TestValidator<T> extends Validator<T> {
  final void Function(T? value) validateFn;

  TestValidator(this.validateFn);

  @override
  Future<void> validate(T? value) async {
    validateFn(value);
  }
}

void main() {
  group('Base Field Tests', () {
    late TestField<String> field;

    setUp(() {
      field = TestField<String>(required: true);
    });

    test('field sets widget is required', () {
      expect(TestField<String>(required: true).widget.isRequired, isTrue);
      expect(TestField<String>(required: false).widget.isRequired, isFalse);
    });

    test('field deep copies widget instance', () {
      final field1 = TestField<String>();
      final field2 = TestField<String>();

      field1.widget = TextInput(attrs: {'class': 'custom-class-1'});
      field2.widget = TextInput(attrs: {'class': 'custom-class-2'});

      expect(field1.widget.attrs['class'], equals('custom-class-1'));
      expect(field2.widget.attrs['class'], equals('custom-class-2'));
    });

    test('disabled field has changed always returns false', () {
      final disabledField = TestField<String>(disabled: true);
      expect(disabledField.hasChanged('x', 'y'), isFalse);
    });

    test('field handles empty values', () async {
      // Required field
      await expectLater(
        () => field.clean(null),
        throwsA(isA<ValidationError>()),
      );

      await expectLater(() => field.clean(''), throwsA(isA<ValidationError>()));

      // Optional field
      field = TestField<String>(required: false);
      expect(await field.clean(null), isNull);
      expect(await field.clean(''), equals(''));
    });

    test('field prepares value for validation', () {
      expect(field.prepareValue('test'), equals('test'));
      expect(field.prepareValue(null), isNull);
    });

    test('field validates using custom validators', () async {
      field = TestField<String>(
        validators: [
          TestValidator<String>((value) {
            if (value == 'invalid') {
              throw ValidationError({
                'invalid': ['Value cannot be "invalid"'],
              });
            }
          }),
        ],
      );

      await field.clean('valid');
      await expectLater(
        () => field.clean('invalid'),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
