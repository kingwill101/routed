import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('ChoiceField Tests', () {
    late ChoiceField field;

    test('test_choicefield_1', () async {
      field = ChoiceField(
        choices: [
          ['1', 'One'],
          ['2', 'Two'],
        ],
      );

      // Test required field validation
      await expectLater(() => field.clean(''), throwsA(isA<ValidationError>()));

      await expectLater(
        () => field.clean(null),
        throwsA(isA<ValidationError>()),
      );

      // Test valid choices
      expect(await field.clean(1), equals('1'));
      expect(await field.clean('1'), equals('1'));

      // Test invalid choice
      await expectLater(
        () => field.clean('3'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            'Select a valid choice. 3 is not one of the available choices.',
          ),
        ),
      );
    });

    test('test_choicefield_2', () async {
      field = ChoiceField(
        choices: [
          ['1', 'One'],
          ['2', 'Two'],
        ],
        required: false,
      );

      // Test optional field
      expect(await field.clean(''), equals(''));
      expect(await field.clean(null), equals(''));

      // Test valid choices
      expect(await field.clean(1), equals('1'));
      expect(await field.clean('1'), equals('1'));

      // Test invalid choice
      await expectLater(
        () => field.clean('3'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            'Select a valid choice. 3 is not one of the available choices.',
          ),
        ),
      );
    });

    test('test_choicefield_3', () async {
      field = ChoiceField(
        choices: [
          ['J', 'John'],
          ['P', 'Paul'],
        ],
      );

      // Test valid choice
      expect(await field.clean('J'), equals('J'));

      // Test using display value instead of actual value
      await expectLater(
        () => field.clean('John'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            'Select a valid choice. John is not one of the available choices.',
          ),
        ),
      );
    });

    test('test_choicefield_4', () async {
      // Test grouped choices
      field = ChoiceField(
        choices: [
          [
            'Numbers',
            [
              ['1', 'One'],
              ['2', 'Two'],
            ],
          ],
          [
            'Letters',
            [
              ['3', 'A'],
              ['4', 'B'],
            ],
          ],
          ['5', 'Other'],
        ],
      );

      // Test valid choices from different groups
      expect(await field.clean(1), equals('1'));
      expect(await field.clean('1'), equals('1'));
      expect(await field.clean(3), equals('3'));
      expect(await field.clean('3'), equals('3'));
      expect(await field.clean(5), equals('5'));
      expect(await field.clean('5'), equals('5'));

      // Test invalid choice
      await expectLater(
        () => field.clean('6'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            'Select a valid choice. 6 is not one of the available choices.',
          ),
        ),
      );
    });

    test('test_choicefield_choices_default', () {
      field = ChoiceField(choices: []);
      expect(field.choices, isEmpty);
    });

    test('test_choicefield_callable', () async {
      List<List<String>> choices() => [
        ['J', 'John'],
        ['P', 'Paul'],
      ];

      field = ChoiceField(choices: choices());
      expect(await field.clean('J'), equals('J'));
    });

    test('test_choicefield_mapping', () async {
      field = ChoiceField(
        choices: {
          'J': 'John',
          'P': 'Paul',
        }.entries.map((e) => [e.key, e.value]).toList(),
      );

      expect(await field.clean('J'), equals('J'));
    });

    test('test_choicefield_grouped_mapping', () async {
      field = ChoiceField(
        choices: [
          [
            'Numbers',
            [
              ['1', 'One'],
              ['2', 'Two'],
            ],
          ],
          [
            'Letters',
            [
              ['3', 'A'],
              ['4', 'B'],
            ],
          ],
        ],
      );

      for (var i in ['1', '2', '3', '4']) {
        expect(await field.clean(i), equals(i));
      }
    });

    test('test_choicefield_disabled', () {
      field = ChoiceField(
        choices: [
          ['J', 'John'],
          ['P', 'Paul'],
        ],
        disabled: true,
      );

      expect(field.widget.attrs['disabled'], equals('disabled'));
    });
  });
}
