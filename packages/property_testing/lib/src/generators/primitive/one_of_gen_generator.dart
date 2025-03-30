import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator that selects one generator from a provided list and uses it to generate a value.
///
/// Shrinking attempts to use generators earlier in the list or to shrink the value
/// using the originally chosen generator's shrinking logic.
class OneOfGenGenerator<T> extends Generator<T> {
  final List<Generator<T>> generators;

  OneOfGenGenerator(this.generators) {
    if (generators.isEmpty) {
      throw ArgumentError('generators must not be empty');
    }
  }

  @override
  ShrinkableValue<T> generate(Random random) {
    final generatorIndex = random.nextInt(generators.length);
    final chosenGenerator = generators[generatorIndex];
    final shrinkableValue = chosenGenerator.generate(random);

    // Shrinking for oneOfGen:
    // 1. Try using generators earlier in the list (generating a fresh value).
    // 2. Try shrinking the value produced by the originally chosen generator.
    return ShrinkableValue(shrinkableValue.value, () sync* {
      // 1. Try earlier generators
      for (var i = 0; i < generatorIndex; i++) {
        // This generates a potentially completely different *type* of value
        // from the earlier generator, which might pass the test.
        yield generators[i].generate(random);
      }

      // 2. Try shrinking the current value using its own shrink logic
      yield* shrinkableValue.shrinks();
    });
  }
} 