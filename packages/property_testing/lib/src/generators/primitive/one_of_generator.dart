import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator that selects one value from a provided list.
///
/// Shrinking attempts to yield values earlier in the list.
class OneOfGenerator<T> extends Generator<T> {
  final List<T> values;

  OneOfGenerator(this.values) {
    if (values.isEmpty) {
      throw ArgumentError('values must not be empty');
    }
  }

  @override
  ShrinkableValue<T> generate(Random random) {
    final value = values[random.nextInt(values.length)];

    // Shrinking for oneOf: yield values earlier in the list.
    return ShrinkableValue(value, () sync* {
      final index = values.indexOf(value);
      for (var i = 0; i < index; i++) {
        // Check if the earlier value is actually different
        if (values[i] != value) {
             yield ShrinkableValue.leaf(values[i]);
        }
      }
    });
  }
} 