import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('InertiaRequest', () {
    test('parses headers', () {
      final request = InertiaRequest(
        headers: {
          'X-Inertia': 'true',
          'X-Inertia-Version': '1.2.3',
          'X-Inertia-Partial-Data': 'name,team',
          'X-Inertia-Partial-Component': 'Team',
          'X-Inertia-Reset': 'team',
        },
        url: '/teams',
        method: 'GET',
      );

      expect(request.isInertia, isTrue);
      expect(request.version, equals('1.2.3'));
      expect(request.partialData, equals(['name', 'team']));
      expect(request.partialComponent, equals('Team'));
      expect(request.resetKeys, equals(['team']));
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

      final partial = request.createPartialContext(['team']);
      expect(partial.isPartialReload, isTrue);
      expect(partial.requestedProps, equals(['team']));

      final deferred = request.createDeferredContext(['default']);
      expect(deferred.requestedDeferredGroups, equals(['default']));
    });
  });
}
