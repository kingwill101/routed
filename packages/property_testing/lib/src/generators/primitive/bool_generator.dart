import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator for boolean values with shrinking capabilities.
///
/// True values shrink to false, while false values cannot be shrunk further.
class BoolGenerator extends Generator<bool> {
  @override
  ShrinkableValue<bool> generate(Random random) {
    final value = random.nextBool();

    // Boolean shrinking: true shrinks to false, false cannot shrink.
    // Using a different approach to ensure the PropertyTestRunner picks up the shrunk value
    if (value) {
      return ShrinkableValue<bool>(value, () sync* {
        // When true, yield the shrunk false value directly
        yield ShrinkableValue.leaf(false);
      });
    } else {
      // When false, no shrinking needed
      return ShrinkableValue.leaf(value);
    }
  }
}
