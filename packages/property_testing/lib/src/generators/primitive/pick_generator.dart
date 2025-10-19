import 'dart:math' show Random;

import '../../generator_base.dart';
import 'sampling_generator.dart';

/// A generator that selects exactly [count] unique elements from a list of options.
class PickGenerator<T> extends SamplingGenerator<T> {
  final int count;

  PickGenerator(this.count, List<T> options) : super(options) {
    if (count < 0 || count > options.length) {
      throw ArgumentError(
        'count ($count) must be between 0 and options.length (${options.length})',
      );
    }
  }

  @override
  ShrinkableValue<List<T>> generate(Random random) {
    final value = selectItems(count, random);
    return ShrinkableValue(
      value,
      () => shrinkList(value, count),
    ); // minCount is fixed at count
  }
}
