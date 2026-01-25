/// Tests for header utilities and property context helpers.
library;
import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs header and context unit tests.
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

      test('extracts partial except data', () {
        final headers = {'X-Inertia-Partial-Except': 'prop1,prop2'};
        final partialExcept = InertiaHeaderUtils.getPartialExcept(headers);

        expect(partialExcept, orderedEquals(['prop1', 'prop2']));
      });

      test('extracts error bag header', () {
        final headers = {'X-Inertia-Error-Bag': 'login'};
        expect(InertiaHeaderUtils.getErrorBag(headers), equals('login'));
      });

      test('extracts merge intent header', () {
        final headers = {'X-Inertia-Infinite-Scroll-Merge-Intent': 'prepend'};
        expect(InertiaHeaderUtils.getMergeIntent(headers), equals('prepend'));
      });

      test('extracts except-once props', () {
        final headers = {'X-Inertia-Except-Once-Props': 'a,b'};
        expect(
          InertiaHeaderUtils.getExceptOnceProps(headers),
          orderedEquals(['a', 'b']),
        );
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
