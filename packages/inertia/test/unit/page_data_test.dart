import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('PageData', () {
    test('builds from context headers', () {
      final page = PageData.fromContext(
        'Home',
        {'name': 'Ada'},
        '/home',
        {'X-Inertia-Version': '123', 'X-Inertia-History': 'encrypt,clear'},
      );

      expect(page.version, equals('123'));
      expect(page.encryptHistory, isTrue);
      expect(page.clearHistory, isTrue);
    });

    test('serializes optional fields', () {
      final page = PageData(
        component: 'Home',
        props: {'name': 'Ada'},
        url: '/home',
        deferredProps: {
          'default': ['lazy'],
        },
        mergeProps: ['merge'],
      );

      final json = page.toJson();
      expect(json['deferredProps'], isNotNull);
      expect(json['mergeProps'], equals(['merge']));
    });
  });
}
