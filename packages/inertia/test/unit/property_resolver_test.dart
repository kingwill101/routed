/// Tests for [PropertyResolver] behavior.
library;
import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

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

    test('skips deferred props on initial load', () {
      final props = {'deferred': DeferredProp(() => 'later', group: 'custom')};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props.containsKey('deferred'), isFalse);
      expect(result.deferredProps['custom'], contains('deferred'));
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
