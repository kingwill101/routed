/// Tests for [InertiaResponseFactory] behavior.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs response factory unit tests.
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
      expect(page.props.containsKey('lazy'), isFalse);
    });

    test('builds async page data with resolved props', () async {
      final context = PropertyContext.partial(
        headers: {
          'X-Inertia-Partial-Data': 'user,lazy',
          'X-Inertia-Partial-Component': 'Home',
        },
        requestedProps: ['user', 'lazy'],
      );
      final page = await InertiaResponseFactory().buildPageDataAsync(
        component: 'Home',
        props: {
          'user': Future.value({'name': 'Ada'}),
          'lazy': LazyProp(() async => 'Lazy'),
        },
        url: '/home',
        context: context,
      );

      expect(page.props['user'], equals({'name': 'Ada'}));
      expect(page.props['lazy'], equals('Lazy'));
    });

    test('builds async json response with headers', () async {
      final context = PropertyContext(headers: {});
      final response = await InertiaResponseFactory().jsonResponseAsync(
        component: 'Async',
        props: {'value': Future.value('ok')},
        url: '/async',
        context: context,
      );

      expect(response.isInertia, isTrue);
      expect(response.headers['Content-Type'], equals('application/json'));
      expect(response.page.props['value'], equals('ok'));
    });

    test('includes deferred and merge metadata', () {
      final props = {
        'user': {'name': 'Ada'},
        'deferred': DeferredProp(() => 'later', group: 'default'),
        'custom': DeferredProp(() => 'custom', group: 'custom'),
        'merge': MergeProp(() => 'value'),
        'prepend': MergeProp(() => 'value')..prepend(),
        'deep': MergeProp(() => 'value', deepMerge: true)..matchOn(['id']),
        'scroll': ScrollProp(
          () => {
            'data': [1],
          },
        ),
      };

      final context = PropertyContext(headers: {});
      final page = InertiaResponseFactory().buildPageData(
        component: 'Home',
        props: props,
        url: '/home',
        context: context,
      );

      expect(page.deferredProps?['default'], equals(['deferred']));
      expect(page.deferredProps?['custom'], equals(['custom']));
      expect(page.mergeProps, contains('merge'));
      expect(page.prependProps, contains('prepend'));
      expect(page.deepMergeProps, contains('deep'));
      expect(page.matchPropsOn, contains('deep.id'));
      expect(page.scrollProps?.containsKey('scroll'), isTrue);
    });

    test('includes once metadata in page data', () {
      final props = {
        'token': OnceProp(() => 'secret', ttl: Duration(seconds: 1)),
      };

      final context = PropertyContext(headers: {'X-Inertia': 'true'});
      final page = InertiaResponseFactory().buildPageData(
        component: 'Home',
        props: props,
        url: '/home',
        context: context,
      );

      expect(page.onceProps?.containsKey('token'), isTrue);
      expect(page.props['token'], equals('secret'));
    });
  });
}
