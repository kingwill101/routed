import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('SlugField', () {
    test('normalization', () async {
      final field = SlugField();
      expect(await field.clean('    aa-bb-cc    '), equals('aa-bb-cc'));
    });

    test('unicode normalization', () async {
      final field = SlugField(allowUnicode: true);
      expect(await field.clean('a'), equals('a'));
      expect(await field.clean('1'), equals('1'));
      expect(await field.clean('a1'), equals('a1'));
      expect(await field.clean('你好'), equals('你好'));
      expect(await field.clean('  你-好  '), equals('你-好'));
      expect(await field.clean('ıçğüş'), equals('ıçğüş'));
      expect(await field.clean('foo-ıç-bar'), equals('foo-ıç-bar'));
    });

    test('empty value handling', () async {
      final field = SlugField(required: false);
      expect(await field.clean(''), equals(''));
      expect(await field.clean(null), equals(''));

      final fieldWithNullEmpty = SlugField(required: false, emptyValue: null);
      expect(await fieldWithNullEmpty.clean(''), equals(null));
      expect(await fieldWithNullEmpty.clean(null), equals(null));
    });

    test('invalid values', () async {
      final field = SlugField();
      expect(
        () => field.clean('spaces not allowed'),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => field.clean('special!@#chars'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('min length validation', () async {
      final field = SlugField(minLength: 3);
      expect(() => field.clean('ab'), throwsA(isA<ValidationError>()));
      expect(await field.clean('abc'), equals('abc'));
    });

    test('max length validation', () async {
      final field = SlugField(maxLength: 5);
      expect(await field.clean('abcde'), equals('abcde'));
      expect(() => field.clean('abcdef'), throwsA(isA<ValidationError>()));
    });
  });
}
