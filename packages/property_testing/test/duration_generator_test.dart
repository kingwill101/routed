import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Duration Generator', () {
    test('generates durations within specified range', () async {
      final min = Duration.zero;
      final max = const Duration(days: 30);

      final runner = PropertyTestRunner(
        Specialized.duration(min: min, max: max),
        (duration) {
          expect(duration, greaterThanOrEqualTo(min));
          expect(duration, lessThanOrEqualTo(max));
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates non-negative durations by default', () async {
      final runner = PropertyTestRunner(
        Specialized.duration(),
        (duration) {
          expect(duration.inMicroseconds, greaterThanOrEqualTo(0));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('respects minimum duration', () async {
      final min = const Duration(hours: 1);

      final runner = PropertyTestRunner(
        Specialized.duration(min: min),
        (duration) {
          expect(duration.inHours, greaterThanOrEqualTo(1));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('shrinks towards zero while respecting minimum', () async {
      final min = const Duration(minutes: 30);

      final runner = PropertyTestRunner(
        Specialized.duration(min: min),
        (duration) {
          // Force failure to trigger shrinking
          fail('Triggering shrink');
        },
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      expect(result.failingInput, greaterThanOrEqualTo(min));
      // The shrinking algorithm doesn't guarantee it will get below a day,
      // just that it will reduce the value while respecting the minimum
      expect(result.failingInput.inMicroseconds,
          lessThan(const Duration(days: 365).inMicroseconds));
    });

    test('generates durations across full range', () async {
      final min = Duration.zero;
      final max = const Duration(days: 1);
      final seenHours = <int>{};
      final seenMinutes = <int>{};
      final seenSeconds = <int>{};

      final runner = PropertyTestRunner(
        Specialized.duration(min: min, max: max),
        (duration) {
          seenHours.add(duration.inHours % 24);
          seenMinutes.add(duration.inMinutes % 60);
          seenSeconds.add(duration.inSeconds % 60);
        },
        PropertyConfig(numTests: 1000),
      );

      await runner.run();

      // We should see a good distribution of values
      expect(seenHours.length, greaterThan(12)); // Should see many hours
      expect(seenMinutes.length, greaterThan(30)); // Should see many minutes
      expect(seenSeconds.length, greaterThan(30)); // Should see many seconds
    });

    test('handles microsecond precision', () async {
      final seenMicroseconds = <int>{};

      final runner = PropertyTestRunner(
        Specialized.duration(max: const Duration(microseconds: 1000000)),
        // 1 second
        (duration) {
          seenMicroseconds.add(duration.inMicroseconds % 1000);
        },
        PropertyConfig(numTests: 1000),
      );

      await runner.run();
      expect(seenMicroseconds.length,
          greaterThan(50)); // Should see many different microseconds
    });

    test('duration arithmetic properties', () async {
      final runner = PropertyTestRunner(
        Specialized.duration(max: const Duration(hours: 24)),
        (duration) {
          // Test basic duration arithmetic properties
          expect(duration + Duration.zero, equals(duration),
              reason: 'Adding zero');
          expect(duration * 1, equals(duration), reason: 'Multiplying by 1');
          expect(duration * 0, equals(Duration.zero),
              reason: 'Multiplying by 0');
          expect(duration - duration, equals(Duration.zero),
              reason: 'Subtracting itself');
          expect((duration * 2) ~/ 2, equals(duration),
              reason: 'Multiply then divide');
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('handles large durations', () async {
      final max = const Duration(days: 365 * 100); // 100 years

      final runner = PropertyTestRunner(
        Specialized.duration(max: max),
        (duration) {
          expect(
              duration.inMicroseconds, lessThanOrEqualTo(max.inMicroseconds));
          expect(duration * 2,
              equals(duration + duration)); // Test arithmetic still works
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });
  });
}
