import 'dart:math' show Random;

import '../../generator_base.dart';
import 'sampling_generator.dart';

/// A generator that selects a variable number of unique elements from a list of options.
///
/// The number of elements is between [min] and [max] inclusive.
class SomeOfGenerator<T> extends SamplingGenerator<T> {
  final int min;
  final int max;

  SomeOfGenerator(List<T> options, {int? min, int? max})
    : min = min ?? 0,
      max = max ?? options.length,
      super(options) {
    if (this.min < 0 || this.min > options.length) {
      throw ArgumentError(
        'min (${this.min}) must be between 0 and options.length (${options.length})',
      );
    }
    if (this.max < this.min || this.max > options.length) {
      throw ArgumentError(
        'max (${this.max}) must be between min (${this.min}) and options.length (${options.length})',
      );
    }
  }

  @override
  ShrinkableValue<List<T>> generate(Random random) {
    final count = min + random.nextInt(max - min + 1);
    final value = selectItems(count, random);
    return ShrinkableValue(
      value,
      () => shrinkList(value, min),
    ); // Use dynamic minCount
  }
}
