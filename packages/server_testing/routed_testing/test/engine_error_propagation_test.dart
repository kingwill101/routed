// @Timeout controls how long we wait if things get swallowed/hang
@Timeout(Duration(seconds: 10))
library;

import 'package:test/test.dart';
import 'package:routed_testing/routed_testing.dart';

void main() {
  group('engineGroup error propagation', () {
    engineGroup(
      'group with intentionally failing tests',
      define: (engine, client, et) {
        et('throws should be surfaced (not swallowed)', (engine, client) async {
          await expectLater(
            () async => throw StateError('boom from engineGroup test'),
            throwsA(isA<StateError>()),
          );
        });

        et('expect failure should be surfaced (not swallowed)', (
          engine,
          client,
        ) async {
          await expectLater(
            () async => expect('actual', equals('expected')),
            throwsA(isA<TestFailure>()),
          );
        });
      },
    );
  });

  group('engineTest error propagation', () {
    engineTest('single engineTest that throws (not swallowed)', (
      engine,
      client,
    ) async {
      await expectLater(
        () async => throw StateError('boom from single engineTest'),
        throwsA(isA<StateError>()),
      );
    });

    engineTest('single engineTest with expect failure (not swallowed)', (
      engine,
      client,
    ) async {
      await expectLater(() async => expect(1, 2), throwsA(isA<TestFailure>()));
    });
  });
}
