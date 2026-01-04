import 'dart:async';
import 'dart:io' show sleep;

import 'package:server_testing/src/browser/browser_config.dart';
import 'package:test/test.dart';

// Test waiter implementation to test the enhanced error messages
class TestAsyncWaiter {
  final Duration defaultTimeout;

  TestAsyncWaiter(this.defaultTimeout);

  Future<void> _waitUntil(
    Future<bool> Function() predicate, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 100),
    String? operation,
    String? selector,
  }) async {
    final startTime = DateTime.now();
    final endTime = startTime.add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      if (await predicate()) return;
      await Future<void>.delayed(interval);
    }

    final elapsed = DateTime.now().difference(startTime);
    final message = _buildTimeoutMessage(operation, selector, timeout, elapsed);
    throw TimeoutException(message, timeout);
  }

  String _buildTimeoutMessage(
    String? operation,
    String? selector,
    Duration timeout,
    Duration elapsed,
  ) {
    final buffer = StringBuffer();

    if (operation != null) {
      buffer.write('$operation failed: ');
    }

    buffer.write('Condition not met within ${timeout.inMilliseconds}ms');

    if (selector != null) {
      buffer.write(' for selector "$selector"');
    }

    buffer.write(' (elapsed: ${elapsed.inMilliseconds}ms)');

    return buffer.toString();
  }

  Future<void> waitFor(String selector, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(
      () async => false, // Always fail for testing
      timeout: timeout,
      operation: 'Wait for element',
      selector: selector,
    );
  }

  Future<void> waitForText(String text, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(
      () async => false, // Always fail for testing
      timeout: timeout,
      operation: 'Wait for text "$text"',
    );
  }

  Future<void> waitForUrl(String url, [Duration? timeout]) async {
    timeout ??= defaultTimeout;
    await _waitUntil(
      () async => false, // Always fail for testing
      timeout: timeout,
      operation: 'Wait for URL path "$url"',
    );
  }
}

class TestSyncWaiter {
  final Duration defaultTimeout;

  TestSyncWaiter(this.defaultTimeout);

  void _waitUntil(
    bool Function() predicate, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 100),
    String? operation,
    String? selector,
  }) {
    final startTime = DateTime.now();
    final endTime = startTime.add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      if (predicate()) return;
      sleep(interval);
    }

    final elapsed = DateTime.now().difference(startTime);
    final message = _buildTimeoutMessage(operation, selector, timeout, elapsed);
    throw TimeoutException(message, timeout);
  }

  String _buildTimeoutMessage(
    String? operation,
    String? selector,
    Duration timeout,
    Duration elapsed,
  ) {
    final buffer = StringBuffer();

    if (operation != null) {
      buffer.write('$operation failed: ');
    }

    buffer.write('Condition not met within ${timeout.inMilliseconds}ms');

    if (selector != null) {
      buffer.write(' for selector "$selector"');
    }

    buffer.write(' (elapsed: ${elapsed.inMilliseconds}ms)');

    return buffer.toString();
  }

  void waitFor(String selector, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(
      () => false, // Always fail for testing
      timeout: timeout,
      operation: 'Wait for element',
      selector: selector,
    );
  }

  void waitForText(String text, [Duration? timeout]) {
    timeout ??= defaultTimeout;
    _waitUntil(
      () => false, // Always fail for testing
      timeout: timeout,
      operation: 'Wait for text "$text"',
    );
  }
}

void main() {
  group('Enhanced Waiter Tests', () {
    group('Timeout Configuration', () {
      test('waiter uses browser config defaultWaitTimeout', () {
        final config = BrowserConfig(
          defaultWaitTimeout: const Duration(milliseconds: 500),
        );
        final waiter = TestAsyncWaiter(config.defaultWaitTimeout);
        expect(waiter.defaultTimeout, equals(config.defaultWaitTimeout));
      });

      test('waiter uses different timeout when configured', () {
        final config = BrowserConfig(
          defaultWaitTimeout: const Duration(seconds: 15),
        );
        final waiter = TestAsyncWaiter(config.defaultWaitTimeout);
        expect(waiter.defaultTimeout, equals(const Duration(seconds: 15)));
      });
    });

    group('Enhanced Error Messages - Async', () {
      late TestAsyncWaiter waiter;

      setUp(() {
        waiter = TestAsyncWaiter(const Duration(milliseconds: 100));
      });

      test('waitFor throws TimeoutException with enhanced message', () async {
        expect(
          () => waiter.waitFor(
            '#missing-element',
            const Duration(milliseconds: 50),
          ),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('Wait for element failed'),
                contains('selector "#missing-element"'),
                contains('50ms'),
                contains('elapsed:'),
              ]),
            ),
          ),
        );
      });

      test(
        'waitForText throws TimeoutException with enhanced message',
        () async {
          expect(
            () => waiter.waitForText(
              'Missing text',
              const Duration(milliseconds: 75),
            ),
            throwsA(
              isA<TimeoutException>().having(
                (e) => e.message,
                'message',
                allOf([
                  contains('Wait for text "Missing text" failed'),
                  contains('75ms'),
                  contains('elapsed:'),
                ]),
              ),
            ),
          );
        },
      );

      test(
        'waitForUrl throws TimeoutException with enhanced message',
        () async {
          expect(
            () => waiter.waitForUrl(
              '/expected-path',
              const Duration(milliseconds: 60),
            ),
            throwsA(
              isA<TimeoutException>().having(
                (e) => e.message,
                'message',
                allOf([
                  contains('Wait for URL path "/expected-path" failed'),
                  contains('60ms'),
                  contains('elapsed:'),
                ]),
              ),
            ),
          );
        },
      );

      test('uses default timeout when none provided', () async {
        expect(
          () => waiter.waitFor('#test-element'),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              contains('100ms'), // Default timeout
            ),
          ),
        );
      });
    });

    group('Enhanced Error Messages - Sync', () {
      late TestSyncWaiter waiter;

      setUp(() {
        waiter = TestSyncWaiter(const Duration(milliseconds: 100));
      });

      test('waitFor throws TimeoutException with enhanced message', () {
        expect(
          () => waiter.waitFor(
            '#missing-element',
            const Duration(milliseconds: 50),
          ),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('Wait for element failed'),
                contains('selector "#missing-element"'),
                contains('50ms'),
                contains('elapsed:'),
              ]),
            ),
          ),
        );
      });

      test('waitForText throws TimeoutException with enhanced message', () {
        expect(
          () => waiter.waitForText(
            'Missing text',
            const Duration(milliseconds: 75),
          ),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('Wait for text "Missing text" failed'),
                contains('75ms'),
                contains('elapsed:'),
              ]),
            ),
          ),
        );
      });

      test('uses default timeout when none provided', () {
        expect(
          () => waiter.waitFor('#test-element'),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              contains('100ms'), // Default timeout
            ),
          ),
        );
      });
    });

    group('Error Message Components', () {
      test('message includes operation when provided', () async {
        final waiter = TestAsyncWaiter(const Duration(milliseconds: 50));

        expect(
          () => waiter.waitFor('#test'),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              startsWith('Wait for element failed:'),
            ),
          ),
        );
      });

      test('message includes selector when provided', () async {
        final waiter = TestAsyncWaiter(const Duration(milliseconds: 50));

        expect(
          () => waiter.waitFor('#complex-selector'),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              contains('selector "#complex-selector"'),
            ),
          ),
        );
      });

      test('message includes timeout duration', () async {
        final waiter = TestAsyncWaiter(const Duration(milliseconds: 50));

        expect(
          () => waiter.waitFor('#test', const Duration(milliseconds: 123)),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              contains('123ms'),
            ),
          ),
        );
      });

      test('message includes elapsed time', () async {
        final waiter = TestAsyncWaiter(const Duration(milliseconds: 50));

        expect(
          () => waiter.waitFor('#test'),
          throwsA(
            isA<TimeoutException>().having(
              (e) => e.message,
              'message',
              contains('elapsed:'),
            ),
          ),
        );
      });
    });

    group('Timing Accuracy', () {
      test('elapsed time is reasonably accurate for async waiter', () async {
        final waiter = TestAsyncWaiter(const Duration(milliseconds: 100));
        final stopwatch = Stopwatch()..start();

        try {
          await waiter.waitFor('#test', const Duration(milliseconds: 100));
        } catch (e) {
          stopwatch.stop();
          final elapsed = stopwatch.elapsedMilliseconds;

          // Should be close to 100ms, allow some tolerance
          expect(elapsed, greaterThanOrEqualTo(90));
          expect(elapsed, lessThan(220));

          // Error message should include an elapsed time close to measured
          final match = RegExp(r'elapsed: (\d+)ms').firstMatch(e.toString());
          expect(match, isNotNull);
          final reported = int.parse(match!.group(1)!);
          expect((reported - elapsed).abs(), lessThanOrEqualTo(10));
        }
      });

      test('elapsed time is reasonably accurate for sync waiter', () {
        final waiter = TestSyncWaiter(const Duration(milliseconds: 100));
        final stopwatch = Stopwatch()..start();

        try {
          waiter.waitFor('#test', const Duration(milliseconds: 100));
        } catch (e) {
          stopwatch.stop();
          final elapsed = stopwatch.elapsedMilliseconds;

          // Should be close to 100ms, allow some tolerance
          expect(elapsed, greaterThanOrEqualTo(90));
          expect(elapsed, lessThan(150));

          // Error message should include an elapsed time close to measured
          final match = RegExp(r'elapsed: (\d+)ms').firstMatch(e.toString());
          expect(match, isNotNull);
          final reported = int.parse(match!.group(1)!);
          expect((reported - elapsed).abs(), lessThanOrEqualTo(10));
        }
      });
    });
  });
}
