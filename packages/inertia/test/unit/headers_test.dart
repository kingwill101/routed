import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

void main() {
  group('Inertia Core', () {
    group('Header Utilities', () {
      test('detects Inertia request', () {
        final headers = {'X-Inertia': 'true'};
        expect(
          InertiaHeaderUtils.isInertiaRequest(headers),
          isTrue,
          reason: 'Should detect Inertia request',
        );
      });

      test('extracts version header', () {
        final headers = {'X-Inertia-Version': '1.0.0'};
        expect(
          InertiaHeaderUtils.getVersion(headers),
          equals('1.0.0'),
          reason: 'Should extract version header',
        );
      });

      test('extracts partial data', () {
        final headers = {'X-Inertia-Partial-Data': 'prop1,prop2'};
        final partialData = InertiaHeaderUtils.getPartialData(headers);

        expect(partialData, isNotNull);
        expect(partialData, orderedEquals(['prop1', 'prop2']));
      });
    });

    group('Property Context', () {
      test('creates basic context', () {
        final context = PropertyContext(
          headers: {},
          shouldIncludeProp: (key) => true,
        );

        expect(context.isInertiaRequest, isFalse);
        expect(context.inertiaVersion, isNull);
        expect(context.partialData, isNull);
      });

      test('creates partial context', () {
        final context = PropertyContext.partial(
          headers: {},
          requestedProps: ['user', 'posts'],
        );

        expect(context.isPartialReload, isTrue);
        expect(context.requestedProps, orderedEquals(['user', 'posts']));
      });
    });
  });
}
