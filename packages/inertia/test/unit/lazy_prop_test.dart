import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('LazyProp', () {
    test('resolves value when requested', () {
      final prop = LazyProp(() => 'lazy-value');
      final context = PropertyContext(headers: {});

      final value = prop.resolve('lazy', context);
      expect(value, equals('lazy-value'));
    });

    test('skips value on partial reload when not requested', () {
      final prop = LazyProp(() => 'lazy-value');
      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['other'],
      );

      expect(() => prop.resolve('lazy', context), throwsException);
    });
  });
}
