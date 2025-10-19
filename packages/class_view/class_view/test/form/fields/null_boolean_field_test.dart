import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('NullBooleanField Tests', () {
    late NullBooleanField field;

    setUp(() {
      field = NullBooleanField();
    });

    test('test_nullbooleanfield_clean', () async {
      // Test empty values
      expect(await field.clean(''), isNull);
      expect(await field.clean(null), isNull);

      // Test boolean values
      expect(await field.clean(true), isTrue);
      expect(await field.clean(false), isFalse);

      // Test string values
      expect(await field.clean('0'), isFalse);
      expect(await field.clean('1'), isTrue);
      expect(await field.clean('2'), isNull);
      expect(await field.clean('3'), isNull);
      expect(await field.clean('hello'), isNull);
      expect(await field.clean('true'), isTrue);
      expect(await field.clean('false'), isFalse);
    });

    test('test_nullbooleanfield_2', () async {
      // Test hidden input with initial values
      final form = NullBooleanField(widget: HiddenInput(), initial: true);

      expect(form.widget, isA<HiddenInput>());
      expect(form.initial, isTrue);

      final form2 = NullBooleanField(widget: HiddenInput(), initial: false);

      expect(form2.widget, isA<HiddenInput>());
      expect(form2.initial, isFalse);
    });

    test('test_nullbooleanfield_3', () async {
      // Test cleaning values with hidden input
      final form = NullBooleanField(widget: HiddenInput());

      expect(await form.clean('True'), isTrue);
      expect(await form.clean('False'), isFalse);
    });

    test('test_nullbooleanfield_4', () async {
      // Test MySQL compatibility (using 0 and 1)
      final choices = [
        ['1', 'Yes'],
        ['0', 'No'],
        ['', 'Unknown'],
      ];

      final form = NullBooleanField(
        widget: NullBooleanSelect(attrs: {'choices': choices}),
      );

      expect(await form.clean('1'), isTrue);
      expect(await form.clean('0'), isFalse);
      expect(await form.clean(''), isNull);
    });

    test('test_nullbooleanfield_changed', () {
      // Test has_changed functionality
      expect(field.hasChanged(false, null), isTrue);
      expect(field.hasChanged(null, false), isTrue);
      expect(field.hasChanged(null, null), isFalse);
      expect(field.hasChanged(false, false), isFalse);
      expect(field.hasChanged(true, false), isTrue);
      expect(field.hasChanged(true, null), isTrue);
      expect(field.hasChanged(true, false), isTrue);

      // Test string values with HiddenInput
      expect(field.hasChanged(false, 'False'), isFalse);
      expect(field.hasChanged(true, 'True'), isFalse);
      expect(field.hasChanged(null, ''), isFalse);
      expect(field.hasChanged(false, 'True'), isTrue);
      expect(field.hasChanged(true, 'False'), isTrue);
      expect(field.hasChanged(null, 'False'), isTrue);
    });
  });
}
