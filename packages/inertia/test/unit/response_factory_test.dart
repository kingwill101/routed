import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('InertiaResponseFactory', () {
    test('ignores partial reload for mismatched component', () {
      final context = PropertyContext(
        headers: {
          'X-Inertia-Partial-Data': 'name',
          'X-Inertia-Partial-Component': 'Other',
        },
        isPartialReload: true,
        requestedProps: ['name'],
      );

      final page = InertiaResponseFactory().buildPageData(
        component: 'Home',
        props: {'name': 'Ada', 'lazy': LazyProp(() => 'Lazy')},
        url: '/home',
        context: context,
      );

      expect(page.props['name'], equals('Ada'));
      expect(page.props['lazy'], equals('Lazy'));
    });
  });
}
