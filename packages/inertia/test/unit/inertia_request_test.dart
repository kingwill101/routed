/// Tests for [InertiaRequest] parsing and context helpers.
library;
import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs Inertia request unit tests.
void main() {
  group('InertiaRequest', () {
    test('parses headers', () {
      final request = InertiaRequest(
        headers: {
          'X-Inertia': 'true',
          'X-Inertia-Version': '1.2.3',
          'X-Inertia-Partial-Data': 'name,team',
          'X-Inertia-Partial-Except': 'extra',
          'X-Inertia-Partial-Component': 'Team',
          'X-Inertia-Reset': 'team',
          'X-Inertia-Except-Once-Props': 'once',
          'X-Inertia-Error-Bag': 'login',
          'X-Inertia-Infinite-Scroll-Merge-Intent': 'prepend',
        },
        url: '/teams',
        method: 'GET',
      );

      expect(request.isInertia, isTrue);
      expect(request.version, equals('1.2.3'));
      expect(request.partialData, equals(['name', 'team']));
      expect(request.partialExcept, equals(['extra']));
      expect(request.partialComponent, equals('Team'));
      expect(request.resetKeys, equals(['team']));
      expect(request.errorBag, equals('login'));
      expect(request.exceptOnceProps, equals(['once']));
      expect(request.mergeIntent, equals('prepend'));
      expect(request.isPartialReload, isTrue);
    });

    test('creates contexts', () {
      final request = InertiaRequest(
        headers: const {},
        url: '/home',
        method: 'GET',
      );

      final context = request.createContext(requestedProps: ['name']);
      expect(context.requestedProps, equals(['name']));

      final partial = request.createPartialContext(
        ['team'],
        requestedExceptProps: ['extra'],
      );
      expect(partial.isPartialReload, isTrue);
      expect(partial.requestedProps, equals(['team']));
      expect(partial.requestedExceptProps, equals(['extra']));

      final deferred = request.createDeferredContext(['default']);
      expect(deferred.requestedDeferredGroups, equals(['default']));
    });
  });
}
