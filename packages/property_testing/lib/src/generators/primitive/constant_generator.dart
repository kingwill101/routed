import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator that always produces the same constant value.
///
/// This generator has no shrinking capabilities as the value is already constant.
class ConstantGenerator<T> extends Generator<T> {
  final T value;

  ConstantGenerator(this.value);

  @override
  ShrinkableValue<T> generate(Random random) => ShrinkableValue.leaf(value);
}
