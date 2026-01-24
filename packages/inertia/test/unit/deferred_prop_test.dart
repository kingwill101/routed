import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('DeferredProp', () {
    test('resolves when group requested', () {
      final prop = DeferredProp(() => 'deferred', group: 'custom');
      final context = PropertyContext.deferred(
        headers: {},
        requestedDeferredGroups: ['custom'],
      );

      final value = prop.resolve('deferred', context);
      expect(value, equals('deferred'));
    });

    test('throws when group not requested', () {
      final prop = DeferredProp(() => 'deferred', group: 'custom');
      final context = PropertyContext.deferred(
        headers: {},
        requestedDeferredGroups: ['default'],
      );

      expect(() => prop.resolve('deferred', context), throwsException);
    });
  });
}
