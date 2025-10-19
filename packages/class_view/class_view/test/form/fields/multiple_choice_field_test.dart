import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('MultipleChoiceField Tests', () {
    test('test_multiplechoicefield_1', () {
      final field = MultipleChoiceField(
        choices: [
          ['1', 'One'],
          ['2', 'Two'],
        ],
      );

      expect(
        () => field.toDart(''),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains('required: This field is required.'),
          ),
        ),
      );

      expect(
        () => field.toDart(null),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains('required: This field is required.'),
          ),
        ),
      );

      expect(field.toDart([1]), equals(['1']));
      expect(field.toDart(['1']), equals(['1']));
      expect(field.toDart(['1', '2']), equals(['1', '2']));
      expect(field.toDart([1, '2']), equals(['1', '2']));
      expect(field.toDart([1, '2']), equals(['1', '2']));

      expect(
        () => field.toDart('hello'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains('Enter a list of values.'),
          ),
        ),
      );

      expect(
        () => field.toDart([]),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains('required: This field is required.'),
          ),
        ),
      );

      expect(
        () => field.toDart(() {}),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains('required: This field is required.'),
          ),
        ),
      );

      expect(
        () => field.toDart(['3']),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains(
              'Select a valid choice. 3 is not one of the available choices.',
            ),
          ),
        ),
      );
    });

    test('test_multiplechoicefield_2', () {
      final field = MultipleChoiceField(
        choices: [
          ['1', 'One'],
          ['2', 'Two'],
        ],
        required: false,
      );

      expect(field.toDart(''), equals([]));
      expect(field.toDart(null), equals([]));
      expect(field.toDart([1]), equals(['1']));
      expect(field.toDart(['1']), equals(['1']));
      expect(field.toDart(['1', '2']), equals(['1', '2']));
      expect(field.toDart([1, '2']), equals(['1', '2']));
      expect(field.toDart([1, '2']), equals(['1', '2']));

      expect(
        () => field.toDart('hello'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains('Enter a list of values.'),
          ),
        ),
      );

      expect(field.toDart([]), equals([]));
      expect(field.toDart(() {}), equals([]));

      expect(
        () => field.toDart(['3']),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains(
              'Select a valid choice. 3 is not one of the available choices.',
            ),
          ),
        ),
      );
    });

    test('test_multiplechoicefield_3', () {
      final field = MultipleChoiceField(
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

      expect(field.toDart([1]), equals(['1']));
      expect(field.toDart(['1']), equals(['1']));
      expect(field.toDart([1, 5]), equals(['1', '5']));
      expect(field.toDart([1, '5']), equals(['1', '5']));
      expect(field.toDart(['1', 5]), equals(['1', '5']));
      expect(field.toDart(['1', '5']), equals(['1', '5']));

      expect(
        () => field.toDart(['6']),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains(
              'Select a valid choice. 6 is not one of the available choices.',
            ),
          ),
        ),
      );

      expect(
        () => field.toDart(['1', '6']),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.errorMessages,
            'errorMessages',
            contains(
              'Select a valid choice. 6 is not one of the available choices.',
            ),
          ),
        ),
      );
    });

    test('test_multiplechoicefield_changed', () {
      final field = MultipleChoiceField(
        choices: [
          ['1', 'One'],
          ['2', 'Two'],
          ['3', 'Three'],
        ],
      );

      expect(field.hasChanged(null, null), isFalse);
      expect(field.hasChanged([], null), isFalse);
      expect(field.hasChanged(null, ['1']), isTrue);
      expect(field.hasChanged([1, 2], ['1', '2']), isFalse);
      expect(field.hasChanged([2, 1], ['1', '2']), isFalse);
      expect(field.hasChanged([1, 2], ['1']), isTrue);
      expect(field.hasChanged([1, 2], ['1', '3']), isTrue);
    });

    test('test_disabled_has_changed', () {
      final field = MultipleChoiceField(
        choices: [
          ['1', 'One'],
          ['2', 'Two'],
        ],
        disabled: true,
      );

      expect(field.hasChanged('x', 'y'), isFalse);
    });
  });
}
