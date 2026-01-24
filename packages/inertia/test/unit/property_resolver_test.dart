import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('PropertyResolver', () {
    test('resolves mixed props and deferred props', () {
      final props = {
        'name': 'Ada',
        'lazy': LazyProp(() => 'lazy'),
        'deferred': DeferredProp(() => 'later', group: 'custom'),
        'merge': MergeProp(() => 'merge-value'),
      };

      final context = PropertyContext(
        headers: {},
        requestedDeferredGroups: ['custom'],
      );

      final result = PropertyResolver.resolve(props, context);

      expect(result.props['name'], equals('Ada'));
      expect(result.props['lazy'], equals('lazy'));
      expect(result.props['deferred'], equals('later'));
      expect(result.mergeProps, contains('merge'));
      expect(result.deferredProps, isEmpty);
    });

    test('skips deferred props when group not requested', () {
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

    test('serializes InertiaSerializable values', () {
      final props = {'user': _User('Ada')};

      final context = PropertyContext(headers: {});
      final result = PropertyResolver.resolve(props, context);

      expect(result.props['user'], equals({'name': 'Ada'}));
    });
  });
}

class _User implements InertiaSerializable {
  _User(this.name);

  final String name;

  @override
  Map<String, dynamic> toInertia() => {'name': name};
}
