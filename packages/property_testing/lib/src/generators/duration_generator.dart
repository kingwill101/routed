import 'dart:math' as math;

import '../generator_base.dart';

/// Generator for Duration values
/// A generator that produces [Duration] values within a specified range.
///
/// Allows specifying `min` and `max` duration bounds. Defaults to generating
/// non-negative durations up to one year.
///
/// Shrinking targets zero duration (or the `min` duration), common durations
/// (like 1 second, 1 minute), and progressively smaller durations by halving.
///
/// Usually used via [Specialized.duration].
///
/// ```dart
/// final durationGen = Specialized.duration(
///   min: Duration.zero,
///   max: const Duration(hours: 1),
/// );
/// final runner = PropertyTestRunner(durationGen, (duration) {
///   // Test property with generated duration
/// });
/// await runner.run();
/// ```
class DurationGenerator extends Generator<Duration> {
  final Duration min;
  final Duration max;

  DurationGenerator({
    Duration? min,
    Duration? max,
  })  : min = min ?? Duration.zero,
        max = max ?? const Duration(days: 365);

  @override
  ShrinkableValue<Duration> generate(math.Random random) {
    final minUs = min.inMicroseconds;
    final maxUs = max.inMicroseconds;
    final range = maxUs - minUs;

    // Generate a random duration with microsecond precision
    final value = Duration(
      microseconds:
          range <= 0 ? minUs : minUs + (random.nextDouble() * range).round(),
    );

    return ShrinkableValue(value, () sync* {
      // Try shrinking towards zero while respecting minimum
      var current = value;
      while (current.inMicroseconds > min.inMicroseconds) {
        final next = Duration(
          microseconds: (current.inMicroseconds + min.inMicroseconds) ~/ 2,
        );
        if (next == current) break;
        current = next;
        yield ShrinkableValue.leaf(next);
      }

      // Try common durations if they're within range
      final commonDurations = [
        Duration.zero,
        const Duration(microseconds: 1),
        const Duration(milliseconds: 1),
        const Duration(seconds: 1),
        const Duration(minutes: 1),
        const Duration(hours: 1),
        const Duration(days: 1),
      ];

      for (final duration in commonDurations) {
        if (duration.compareTo(min) >= 0 && duration.compareTo(max) <= 0) {
          yield ShrinkableValue.leaf(duration);
        }
      }

      // Try round numbers if they're within range
      final roundNumbers = [
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
        const Duration(minutes: 30),
        const Duration(hours: 12),
      ];

      for (final duration in roundNumbers) {
        if (duration.compareTo(min) >= 0 && duration.compareTo(max) <= 0) {
          yield ShrinkableValue.leaf(duration);
        }
      }
    });
  }
}
