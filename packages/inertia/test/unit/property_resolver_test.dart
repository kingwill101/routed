/// Tests for [PropertyResolver] behavior.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:inertia_dart/inertia_dart.dart';

/// Runs property resolver unit tests.
void main() {
  group('PropertyResolver', () {
    test('resolves partial props including deferred', () {
      final props = {
        'name': 'Ada',
        'lazy': LazyProp(() => 'lazy'),
        'deferred': DeferredProp(() => 'later', group: 'custom'),
        'merge': MergeProp(() => 'merge-value'),
      };

      final context = PropertyContext.partial(
        headers: {'X-Inertia-Partial-Data': 'name,lazy,deferred,merge'},
        requestedProps: ['name', 'lazy', 'deferred', 'merge'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['name'], equals('Ada'));
      expect(result.props['lazy'], equals('lazy'));
      expect(result.props['deferred'], equals('later'));
      expect(result.mergeProps, contains('merge'));
      expect(result.deferredProps, isEmpty);
    });

    test('always props are included on partial reloads', () {
      final props = {
        'always': AlwaysProp(() => 'value'),
        'lazy': LazyProp(() => 'lazy'),
      };

      final context = PropertyContext.partial(
        headers: {'X-Inertia-Partial-Data': 'lazy'},
        requestedProps: ['lazy'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['always'], equals('value'));
      expect(result.props['lazy'], equals('lazy'));
    });

    test('skips deferred props on initial load', () {
      final props = {'deferred': DeferredProp(() => 'later', group: 'custom')};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('deferred'), isFalse);
      expect(result.deferredProps['custom'], contains('deferred'));
    });

    test('records deferred props for multiple groups', () {
      final props = {
        'one': DeferredProp(() => 'one', group: 'default'),
        'two': DeferredProp(() => 'two', group: 'custom'),
        'three': DeferredProp(() => 'three', group: 'custom'),
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('one'), isFalse);
      expect(result.deferredProps['default'], equals(['one']));
      expect(result.deferredProps['custom'], equals(['two', 'three']));
    });

    test('resolves nested callables', () {
      final props = {
        'person': {
          'name': () => 'Ada',
          'meta': {'role': () => 'Engineer'},
        },
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props['person']['name'], equals('Ada'));
      expect(result.props['person']['meta']['role'], equals('Engineer'));
    });

    test('excludes optional props on first load', () {
      final props = {'name': 'Ada', 'optional': OptionalProp(() => 'hidden')};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('optional'), isFalse);
      expect(result.props['name'], equals('Ada'));
    });

    test('drops merge props when reset', () {
      final props = {'merge': MergeProp(() => 'value')};

      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['merge'],
        resetKeys: ['merge'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['merge'], equals('value'));
      expect(result.mergeProps, isEmpty);
    });

    test('skips merge props when not requested on partial reload', () {
      final props = {'name': 'Ada', 'merge': MergeProp(() => 'value')};

      final context = PropertyContext.partial(
        headers: {},
        requestedProps: ['name'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('merge'), isFalse);
      expect(result.mergeProps, isEmpty);
    });

    test('excludes merge props when listed in partial except', () {
      final props = {'name': 'Ada', 'merge': MergeProp(() => 'value')};

      final context = PropertyContext.partial(
        headers: {'X-Inertia-Partial-Except': 'merge'},
        requestedProps: ['name', 'merge'],
        requestedExceptProps: ['merge'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('merge'), isFalse);
      expect(result.mergeProps, isEmpty);
    });

    test('emits merge metadata variants', () {
      final merge = MergeProp(() => 'value')..append('items', 'id');
      final prepend = MergeProp(() => 'value')..prepend('items');
      final deep = MergeProp(() => 'value', deepMerge: true);

      final props = {'merge': merge, 'prepend': prepend, 'deep': deep};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.mergeProps, contains('merge.items'));
      expect(result.prependProps, contains('prepend.items'));
      expect(result.deepMergeProps, contains('deep'));
      expect(result.matchPropsOn, contains('merge.items.id'));
    });

    test('emits root prepend metadata', () {
      final props = {'prepend': MergeProp(() => 'value')..prepend()};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.prependProps, contains('prepend'));
      expect(result.mergeProps.contains('prepend'), isFalse);
    });

    test('emits nested merge metadata with match-on paths', () {
      final props = {
        'foo': MergeProp(() => {'data': []})..append('data', 'id'),
        'bar': MergeProp(
          () => {
            'data': {'items': []},
          },
        )..prepend('data.items', 'uuid'),
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.mergeProps, contains('foo.data'));
      expect(result.prependProps, contains('bar.data.items'));
      expect(result.matchPropsOn, contains('foo.data.id'));
      expect(result.matchPropsOn, contains('bar.data.items.uuid'));
    });

    test('includes match-on keys for deep merge props', () {
      final props = {
        'deep': MergeProp(() => 'value', deepMerge: true)
          ..matchOn(['foo', 'bar']),
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.deepMergeProps, contains('deep'));
      expect(result.matchPropsOn, contains('deep.foo'));
      expect(result.matchPropsOn, contains('deep.bar'));
    });

    test('emits scroll metadata', () {
      final scroll = ScrollProp(
        () => ['item'],
        metadata: (_) => const ScrollMetadata(
          pageName: 'page',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2,
        ),
      );

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve({'items': scroll}, context);

      expect(result.scrollProps['items']?['pageName'], equals('page'));
      expect(result.scrollProps['items']?['reset'], isFalse);
    });

    test('marks scroll props as reset when requested', () {
      final props = {
        'users': ScrollProp(
          () => {
            'data': [1],
          },
        ),
      };

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia-Partial-Data': 'users',
          'X-Inertia-Reset': 'users',
        },
        requestedProps: ['users'],
        resetKeys: ['users'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.scrollProps['users']?['reset'], isTrue);
      expect(result.mergeProps.contains('users.data'), isFalse);
    });

    test('uses append merge intent by default for scroll props', () {
      final props = {
        'users': ScrollProp(
          () => {
            'data': [1],
          },
        ),
      };

      final context = PropertyContext.partial(
        headers: {'X-Inertia-Partial-Data': 'users'},
        requestedProps: ['users'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.mergeProps, contains('users.data'));
      expect(result.prependProps.contains('users.data'), isFalse);
    });

    test('respects prepend merge intent header for scroll props', () {
      final props = {
        'users': ScrollProp(
          () => {
            'data': [1],
          },
        ),
      };

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia-Partial-Data': 'users',
          'X-Inertia-Infinite-Scroll-Merge-Intent': 'prepend',
        },
        requestedProps: ['users'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.prependProps, contains('users.data'));
      expect(result.mergeProps.contains('users.data'), isFalse);
    });

    test('respects merge intent with custom scroll wrapper', () {
      final props = {
        'users': ScrollProp(
          () => {
            'items': [1],
          },
          wrapper: 'items',
        ),
      };

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia-Partial-Data': 'users',
          'X-Inertia-Infinite-Scroll-Merge-Intent': 'prepend',
        },
        requestedProps: ['users'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.prependProps, contains('users.items'));
      expect(result.mergeProps.contains('users.items'), isFalse);
    });

    test('serializes InertiaSerializable values', () {
      final props = {'user': _User('Ada')};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props['user'], equals({'name': 'Ada'}));
    });

    test('emits once metadata and excludes once props when requested', () {
      final props = {
        'token': OnceProp(() => 'secret', ttl: Duration(seconds: 1)),
      };

      final context = PropertyContext(
        headers: {'X-Inertia': 'true', 'X-Inertia-Except-Once-Props': 'token'},
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('token'), isFalse);
      expect(result.onceProps.containsKey('token'), isTrue);
    });

    test('includes once props when request is not inertia', () {
      final props = {
        'token': OnceProp(() => 'secret', ttl: Duration(seconds: 1)),
      };

      final context = PropertyContext(
        headers: {'X-Inertia-Except-Once-Props': 'token'},
      );
      final result = PropertyResolver.resolve(props, context);

      expect(result.props['token'], equals('secret'));
    });

    test('excludes once deferred props already loaded', () {
      final props = {'defer': DeferredProp(() => 'value', once: true)};

      final context = PropertyContext(
        headers: {'X-Inertia': 'true', 'X-Inertia-Except-Once-Props': 'defer'},
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('defer'), isFalse);
      expect(result.deferredProps.isEmpty, isTrue);
      expect(result.onceProps.containsKey('defer'), isTrue);
    });

    test('includes once deferred props when explicitly requested', () {
      final props = {'defer': DeferredProp(() => 'value', once: true)};

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia': 'true',
          'X-Inertia-Partial-Data': 'defer',
          'X-Inertia-Except-Once-Props': 'defer',
        },
        requestedProps: ['defer'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['defer'], equals('value'));
      expect(result.deferredProps.isEmpty, isTrue);
      expect(result.onceProps.containsKey('defer'), isTrue);
    });

    test('does not exclude once props on partial reloads', () {
      final props = {'token': OnceProp(() => 'secret', ttl: Duration(days: 1))};

      final context = PropertyContext.partial(
        headers: {'X-Inertia': 'true', 'X-Inertia-Except-Once-Props': 'token'},
        requestedProps: ['token'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['token'], equals('secret'));
    });

    test('does not exclude once props that refresh', () {
      final props = {'token': OnceProp(() => 'fresh', refresh: true)};

      final context = PropertyContext(
        headers: {'X-Inertia': 'true', 'X-Inertia-Except-Once-Props': 'token'},
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['token'], equals('fresh'));
    });

    test('records once metadata using custom keys', () {
      final props = {
        'token': OnceProp(
          () => 'secret',
          ttl: Duration(seconds: 5),
          key: 'auth',
        ),
      };

      final context = PropertyContext(headers: {'X-Inertia': 'true'});
      final result = PropertyResolver.resolve(props, context);

      expect(result.onceProps.containsKey('auth'), isTrue);
      final meta = result.onceProps['auth']!;
      expect(meta['prop'], equals('token'));
      expect(meta['expiresAt'], isA<int>());
    });

    test('unpacks top-level dot props', () {
      final props = {
        'auth.user.can': {'do.stuff': true},
        'plain': 'ok',
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('auth.user.can'), isFalse);
      expect(result.props['plain'], equals('ok'));
      final auth = result.props['auth'] as Map<String, dynamic>;
      final user = auth['user'] as Map<String, dynamic>;
      final can = user['can'] as Map<String, dynamic>;
      expect(can['do.stuff'], isTrue);
    });

    test('does not unpack nested dot props', () {
      final props = {
        'auth': {
          'user.can': {'do.stuff': true},
        },
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      final auth = result.props['auth'] as Map<String, dynamic>;
      expect(auth.containsKey('user.can'), isTrue);
      final userCan = auth['user.can'] as Map<String, dynamic>;
      expect(userCan['do.stuff'], isTrue);
    });

    test('filters nested partial props', () {
      final props = {
        'auth': {
          'user': {'name': 'Ada', 'email': 'ada@example.com'},
          'refresh_token': 'value',
          'token': 'secret',
        },
        'shared': {'flash': 'value'},
      };

      final context = PropertyContext.partial(
        headers: {'X-Inertia-Partial-Data': 'auth.user,auth.refresh_token'},
        requestedProps: ['auth.user', 'auth.refresh_token'],
      );

      final result = PropertyResolver.resolve(props, context);

      final auth = result.props['auth'] as Map<String, dynamic>;
      expect(auth.containsKey('token'), isFalse);
      expect(auth['refresh_token'], equals('value'));
      expect(auth['user']['name'], equals('Ada'));
      expect(result.props.containsKey('shared'), isFalse);
    });

    test('excludes nested props from partial response', () {
      final props = {
        'auth': {
          'user': {'name': 'Ada', 'email': 'ada@example.com'},
          'refresh_token': 'value',
        },
        'shared': {'flash': 'value'},
      };

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia-Partial-Data': 'auth',
          'X-Inertia-Partial-Except': 'auth.user',
        },
        requestedProps: ['auth'],
        requestedExceptProps: ['auth.user'],
      );

      final result = PropertyResolver.resolve(props, context);

      final auth = result.props['auth'] as Map<String, dynamic>;
      expect(auth.containsKey('user'), isFalse);
      expect(auth['refresh_token'], equals('value'));
      expect(result.props.containsKey('shared'), isFalse);
    });

    test('excludes deferred scroll props on initial load', () {
      final props = {
        'users': ScrollProp(
          () => {
            'data': [1],
          },
        ).defer(),
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('users'), isFalse);
      expect(result.deferredProps['default'], contains('users'));
      expect(result.scrollProps.isEmpty, isTrue);
    });

    test('resolves deferred scroll props on partial reload', () {
      final props = {
        'users': ScrollProp(
          () => {
            'data': [1],
          },
        ).defer(),
      };

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia': 'true',
          'X-Inertia-Partial-Data': 'users',
          'X-Inertia-Infinite-Scroll-Merge-Intent': 'prepend',
        },
        requestedProps: ['users'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('users'), isTrue);
      expect(result.scrollProps.containsKey('users'), isTrue);
      expect(result.prependProps, contains('users.data'));
    });

    test('uses custom deferred group for scroll props', () {
      final props = {
        'users': ScrollProp(() => {'data': []}).defer('custom'),
      };

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.deferredProps['custom'], contains('users'));
    });

    test('resolves async props and nested futures', () async {
      final props = {
        'name': Future.value('Ada'),
        'lazy': LazyProp(() async => 'lazy'),
        'nested': {
          'user': () async => {'name': 'Grace'},
        },
        'list': [Future.value(1), 2],
        'serializable': _AsyncUser('Linus'),
        'futureUser': Future.value(_User('Turing')),
      };

      final context = PropertyContext.partial(
        headers: {
          'X-Inertia-Partial-Data':
              'name,lazy,nested,list,serializable,futureUser',
        },
        requestedProps: [
          'name',
          'lazy',
          'nested',
          'list',
          'serializable',
          'futureUser',
        ],
      );

      final result = await PropertyResolver.resolveAsync(props, context);

      expect(result.props['name'], equals('Ada'));
      expect(result.props['lazy'], equals('lazy'));
      expect(result.props['nested']['user']['name'], equals('Grace'));
      expect(result.props['list'], equals([1, 2]));
      expect(result.props['serializable'], equals({'name': 'Linus'}));
      expect(result.props['futureUser'], equals({'name': 'Turing'}));
    });

    test('does not treat string props as callables', () {
      final props = {'date': 'date'};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props['date'], equals('date'));
    });
  });
}

/// Test fixture implementing [InertiaSerializable].
class _User implements InertiaSerializable {
  /// Creates a user fixture with [name].
  _User(this.name);

  /// The user name.
  final String name;

  @override
  /// Serializes the user into Inertia props.
  Map<String, dynamic> toInertia() => {'name': name};
}

/// Test fixture that resolves asynchronously.
class _AsyncUser implements InertiaSerializable {
  /// Creates a user fixture with [name].
  _AsyncUser(this.name);

  /// The user name.
  final String name;

  @override
  /// Serializes the user into Inertia props asynchronously.
  Map<String, dynamic> toInertia() => {'name': Future.value(name)};
}
