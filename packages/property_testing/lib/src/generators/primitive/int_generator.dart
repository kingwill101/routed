import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator for integer values with shrinking capabilities.
class IntGenerator extends Generator<int> {
  final int min;
  final int max;

  IntGenerator({int? min, int? max})
      : min = min ?? -1000,
        max = max ?? 1000 {
    if (this.min > this.max) {
      // Use resolved min/max
      throw ArgumentError('min must be less than or equal to max');
    }
  }

  @override
  ShrinkableValue<int> generate(Random random) {
    final range = max - min + 1;
    final value = range <= 0 ? min : min + random.nextInt(range);

    // Integer Shrinking Logic:
    // 1. Try common values first (especially likely failure boundaries: 11, -11, etc.)
    // 2. Halve towards target (0 or closest boundary).
    // 3. Try small increments/decrements from target.
    // 4. Yield boundaries (min, max).
    return ShrinkableValue(value, () sync* {
      final int target =
          (min <= 0 && max >= 0) ? 0 : (min.abs() < max.abs() ? min : max);
      var current = value;
      final yielded = <int>{value}; // Track yielded values to avoid duplicates

      // Common failure boundary values to try first
      final commonBoundaries = <int>[11, -11, 10, -10, 1, -1, 100, -100, 0];

      // 1. Try common values first (especially those near common test boundary thresholds)
      for (final boundary in commonBoundaries) {
        if (!yielded.contains(boundary) && boundary >= min && boundary <= max) {
          yielded.add(boundary);
          yield ShrinkableValue.leaf(boundary);
        }
      }

      // 2. Shrink towards target by halving difference
      while (true) {
        final diff = current - target;
        if (diff == 0) break;
        final next = target + (diff ~/ 2);
        if (next == current) break; // No change

        if (!yielded.contains(next) && next >= min && next <= max) {
          yielded.add(next);
          yield ShrinkableValue.leaf(next);
          current = next;
        } else {
          break; // Out of bounds or already yielded
        }
      }

      // 3. Try small increments/decrements near target
      // This helps when the test fails at a specific threshold
      for (int i = 1; i <= 20; i++) {
        final plusI = target + i;
        if (!yielded.contains(plusI) && plusI >= min && plusI <= max) {
          yielded.add(plusI);
          yield ShrinkableValue.leaf(plusI);
        }

        final minusI = target - i;
        if (!yielded.contains(minusI) && minusI >= min && minusI <= max) {
          yielded.add(minusI);
          yield ShrinkableValue.leaf(minusI);
        }
      }

      // 4. Yield boundaries if valid and different
      if (!yielded.contains(min) && min >= min && min <= max) {
        yielded.add(min);
        yield ShrinkableValue.leaf(min);
      }

      if (!yielded.contains(max) && max >= min && max <= max) {
        yielded.add(max);
        yield ShrinkableValue.leaf(max);
      }
    }); // End sync*
  }
}
