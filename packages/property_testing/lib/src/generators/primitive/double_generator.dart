import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator for double values with shrinking capabilities.
class DoubleGenerator extends Generator<double> {
  final double min;
  final double max;

  DoubleGenerator({double? min, double? max})
      : min = min ?? -1000.0,
        max = max ?? 1000.0 {
    if (this.min > this.max) {
      // Use resolved min/max
      throw ArgumentError('min must be less than or equal to max');
    }
  }

  @override
  ShrinkableValue<double> generate(Random random) {
    // Ensure min and max are finite for generation
    final genMin = min.isFinite ? min : -double.maxFinite;
    final genMax = max.isFinite ? max : double.maxFinite;
    double value;
    if (genMin == genMax) {
      value = genMin;
    } else if (genMin.isFinite && genMax.isFinite) {
      value = genMin + random.nextDouble() * (genMax - genMin);
    } else {
      // Handle infinite ranges - generate around 0 or scale exponentially
      // This is a simplification, could be more sophisticated
      value = (random.nextDouble() - 0.5) * 2000; // Example: range around 0
      if (value < genMin) value = genMin;
      if (value > genMax) value = genMax;
    }

    // Double Shrinking Logic:
    // 1. Try common values first (especially likely failure boundaries: 1.0, -1.0, etc.)
    // 2. Halve towards target (0.0 or closest boundary).
    // 3. Try small increments/decrements from target.
    // 4. Yield boundaries (min, max).
    return ShrinkableValue(value, () sync* {
      // Use original min/max for target calculation
      final double target = (min <= 0.0 && max >= 0.0)
          ? 0.0
          : (min.abs() < max.abs() ? min : max);
      const tolerance = 1e-9;
      var current = value;
      final yielded = <double>{value}; // Track yielded values

      // Common failure boundary values to try first
      final commonBoundaries = <double>[
        1.0,
        -1.0,
        1.001,
        -1.001,
        0.999,
        -0.999,
        0.0,
        0.1,
        -0.1,
        10.0,
        -10.0
      ];

      // 1. Try common values first (especially those near common test boundary thresholds)
      for (final boundary in commonBoundaries) {
        if (!yielded.contains(boundary) &&
            boundary >= min - tolerance &&
            boundary <= max + tolerance) {
          yielded.add(boundary);
          yield ShrinkableValue.leaf(boundary);
        }
      }

      // 2. Shrink towards target by halving difference
      const maxSteps = 100; // Prevent infinite loops
      for (int i = 0; i < maxSteps; ++i) {
        if (!current.isFinite ||
            !target.isFinite ||
            (current - target).abs() <= tolerance) {
          break; // Stop if target reached or non-finite
        }

        final next = target + (current - target) / 2.0;

        if (!next.isFinite) break; // Stop if shrink results in non-finite

        // Ensure progress beyond tolerance
        if ((current - next).abs() <= tolerance) break;
        // Ensure getting closer
        if ((next - target).abs() >= (current - target).abs() - tolerance) {
          break;
        }

        if (!yielded.contains(next) &&
            next >= min - tolerance &&
            next <= max + tolerance) {
          yielded.add(next);
          yield ShrinkableValue.leaf(next);
          current = next;
        } else {
          break; // Out of bounds or already yielded
        }
      }

      // 3. Try small increments/decrements around target
      // Helps find failure boundaries more precisely
      if (target.isFinite) {
        for (double delta = 0.1; delta <= 2.0; delta += 0.1) {
          final above = target + delta;
          if (!yielded.contains(above) &&
              above >= min - tolerance &&
              above <= max + tolerance) {
            yielded.add(above);
            yield ShrinkableValue.leaf(above);
          }

          final below = target - delta;
          if (!yielded.contains(below) &&
              below >= min - tolerance &&
              below <= max + tolerance) {
            yielded.add(below);
            yield ShrinkableValue.leaf(below);
          }
        }

        // Add explicit boundaries for common test values (especially the 1.0 boundary)
        for (double d = 1.0; d <= 1.2; d += 0.01) {
          if (!yielded.contains(d) &&
              d >= min - tolerance &&
              d <= max + tolerance) {
            yielded.add(d);
            yield ShrinkableValue.leaf(d);
          }

          final negD = -d;
          if (!yielded.contains(negD) &&
              negD >= min - tolerance &&
              negD <= max + tolerance) {
            yielded.add(negD);
            yield ShrinkableValue.leaf(negD);
          }
        }
      }

      // 4. Yield boundaries if valid and different
      if (min.isFinite &&
          !yielded.contains(min) &&
          min >= min - tolerance &&
          min <= max + tolerance) {
        yielded.add(min);
        yield ShrinkableValue.leaf(min);
      }
      if (max.isFinite &&
          !yielded.contains(max) &&
          max >= min - tolerance &&
          max <= max + tolerance) {
        yielded.add(max);
        yield ShrinkableValue.leaf(max);
      }
    }); // End sync*
  }
}
