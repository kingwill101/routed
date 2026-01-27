/// Tests for [ScrollProp] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia.dart';

/// Runs scroll prop unit tests.
void main() {
  group('ScrollProp', () {
    test('returns default metadata when none provided', () {
      final prop = ScrollProp(() => ['item']);

      final metadata = prop.metadata();

      expect(metadata.pageName, equals('page'));
      expect(metadata.previousPage, isNull);
      expect(metadata.nextPage, isNull);
      expect(metadata.currentPage, isNull);
    });

    test('uses custom metadata resolver', () {
      final prop = ScrollProp(
        () => ['item'],
        metadata: (_) => const ScrollMetadata(
          pageName: 'users',
          previousPage: 1,
          nextPage: 3,
          currentPage: 2,
        ),
      );

      final metadata = prop.metadata();

      expect(metadata.pageName, equals('users'));
      expect(metadata.previousPage, equals(1));
      expect(metadata.nextPage, equals(3));
      expect(metadata.currentPage, equals(2));
    });

    test('throws when metadata resolver is async', () {
      final prop = ScrollProp(
        () => ['item'],
        metadata: (_) async => const ScrollMetadata(pageName: 'async'),
      );

      expect(() => prop.metadata(), throwsA(isA<StateError>()));
    });

    test('supports async metadata resolution', () async {
      final prop = ScrollProp(
        () => ['item'],
        metadata: (_) async => const ScrollMetadata(pageName: 'async'),
      );

      final metadata = await prop.metadataAsync();

      expect(metadata.pageName, equals('async'));
    });

    test('configures merge intent to append by default', () {
      final prop = ScrollProp(() => ['item']);

      prop.configureMergeIntent(null);

      expect(prop.appendsAtPaths, contains('data'));
      expect(prop.prependsAtPaths, isEmpty);
    });

    test('configures merge intent to prepend', () {
      final prop = ScrollProp(() => ['item']);

      prop.configureMergeIntent('prepend');

      expect(prop.prependsAtPaths, contains('data'));
      expect(prop.appendsAtPaths, isEmpty);
    });

    test('uses custom wrapper for merge intent', () {
      final prop = ScrollProp(() => ['item'], wrapper: 'items');

      prop.configureMergeIntent('prepend');

      expect(prop.prependsAtPaths, contains('items'));
    });
  });
}
