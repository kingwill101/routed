import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('InertiaResponse', () {
    test('builds json response with headers', () {
      final page = PageData(
        component: 'Home',
        props: {'name': 'Ada'},
        url: '/home',
      );

      final response = InertiaResponse.json(page);

      expect(response.isInertia, isTrue);
      expect(response.headers['Content-Type'], equals('application/json'));
      expect(response.headers[InertiaHeaders.inertia], equals('true'));
      expect(
        response.headers[InertiaHeaders.inertiaVary],
        equals(InertiaHeaders.inertia),
      );
      expect(response.toJson()['component'], equals('Home'));
    });

    test('builds html response', () {
      final page = PageData(component: 'Home', props: const {}, url: '/home');

      final response = InertiaResponse.html(page, '<div></div>');

      expect(response.isInertia, isFalse);
      expect(response.html, contains('<div>'));
      expect(
        response.headers['Content-Type'],
        equals('text/html; charset=utf-8'),
      );
    });

    test('builds location response', () {
      final response = InertiaResponse.location('/login');

      expect(response.statusCode, equals(409));
      expect(
        response.headers[InertiaHeaders.inertiaLocation],
        equals('/login'),
      );
      expect(response.page.url, equals('/login'));
    });
  });
}
