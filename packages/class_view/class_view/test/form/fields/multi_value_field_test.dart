import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

// Helper function to check for partial error message
Matcher containsErrorMessage(String message) {
  return predicate<ValidationError>(
    (error) => error.toString().contains(message),
    'contains error message "$message"',
  );
}

const beatles = [
  ['J', 'John'],
  ['P', 'Paul'],
  ['G', 'George'],
  ['R', 'Ringo'],
];

class PartiallyRequiredField extends MultiValueField<String> {
  PartiallyRequiredField({
    super.name,
    required super.required,
    required super.requireAllFields,
  }) : super(
         fields: [CharField(required: true), CharField(required: false)],
         widget: MultiValueWidget(widgets: [TextInput(), TextInput()]),
       );

  @override
  String? compress(List dataList) {
    return dataList
        .where((x) => x != null && x.toString().isNotEmpty)
        .join(',');
  }
}

class ComplexField extends MultiValueField<String> {
  ComplexField({super.name, bool? disabled})
    : super(
        fields: [
          CharField(),
          MultipleChoiceField(choices: beatles),
          DateTimeField(),
        ],
        widget: MultiValueWidget(
          widgets: [
            TextInput(),
            SelectMultiple(choices: beatles),
            DateTimeInput(),
          ],
        ),
        disabled: disabled ?? false,
      );

  @override
  String? compress(List dataList) {
    if (dataList.isEmpty || dataList.any((x) => x == null)) return null;
    final dateTime = dataList[2] as DateTime;
    final formattedDate =
        '${dateTime.year.toString().padLeft(4, '0')}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
    return '${dataList[0]},${(dataList[1] as List).join('')},$formattedDate';
  }

  @override
  List decompressValue(dynamic value) {
    if (value is! String || value.isEmpty) return [];
    final parts = value.split(',');
    if (parts.length != 3) return [];

    return [parts[0], parts[1].split('').toList(), DateTime.parse(parts[2])];
  }
}

void main() {
  group('MultiValueField Tests', () {
    late ComplexField field;

    setUp(() {
      field = ComplexField();
    });

    test('clean valid data', () async {
      final result = await field.clean([
        'some text',
        ['J', 'P'],
        DateTime.parse('2007-04-25 06:24:00'),
      ]);
      expect(result, equals('some text,JP,2007-04-25 06:24:00'));
    });

    test('clean disabled multivalue field', () async {
      final disabledField = ComplexField(disabled: true);

      final inputs = [
        'some text,JP,2007-04-25 06:24:00',
        [
          'some text',
          ['J', 'P'],
          DateTime.parse('2007-04-25 06:24:00'),
        ],
      ];

      for (final data in inputs) {
        final result = await disabledField.clean(data);
        expect(result, equals(inputs[0]));
      }
    });

    test('invalid choice throws validation error', () {
      expect(
        () => field.clean([
          'some text',
          ['X'],
          DateTime.parse('2007-04-25 06:24:00'),
        ]),
        throwsA(containsErrorMessage('Select a valid choice')),
      );
    });

    test('insufficient data throws validation error', () {
      expect(
        () => field.clean([
          'some text',
          ['JP'],
        ]),
        throwsA(containsErrorMessage('This field is required')),
      );
    });

    group('hasChanged tests', () {
      test('no initial data returns true', () {
        expect(
          field.hasChanged(null, [
            'some text',
            ['J', 'P'],
            DateTime.parse('2007-04-25 06:24:00'),
          ]),
          isTrue,
        );
      });

      test('same data returns false', () {
        expect(
          field.hasChanged('some text,JP,2007-04-25 06:24:00', [
            'some text',
            ['J', 'P'],
            DateTime.parse('2007-04-25 06:24:00'),
          ]),
          isFalse,
        );
      });

      test('first widget changed returns true', () {
        expect(
          field.hasChanged('some text,JP,2007-04-25 06:24:00', [
            'other text',
            ['J', 'P'],
            DateTime.parse('2007-04-25 06:24:00'),
          ]),
          isTrue,
        );
      });

      test('last widget changed returns true', () {
        expect(
          field.hasChanged('some text,JP,2007-04-25 06:24:00', [
            'some text',
            ['J', 'P'],
            DateTime.parse('2009-04-25 11:44:00'),
          ]),
          isTrue,
        );
      });

      test('disabled field always returns false', () {
        final disabledField = ComplexField(disabled: true);
        expect(disabledField.hasChanged(['x', 'x'], ['y', 'y']), isFalse);
      });
    });

    group('PartiallyRequiredField tests', () {
      test('validates with required field present', () async {
        final field = PartiallyRequiredField(
          required: true,
          requireAllFields: false,
        );

        final result = await field.clean(['Hello', '']);
        expect(result, equals('Hello'));
      });

      test('fails validation when required field missing', () {
        final field = PartiallyRequiredField(
          required: true,
          requireAllFields: false,
        );

        expect(() => field.clean(['', '']), throwsA(isA<ValidationError>()));
      });
    });
  });
}
