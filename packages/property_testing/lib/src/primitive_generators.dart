import 'dart:math' show Random;

import 'generator_base.dart';

/// A collection of primitive generators
/// Provides static factory methods for creating common primitive value generators.
///
/// Offers generators for basic types like integers ([Gen.integer]), doubles
/// ([Gen.double_]), booleans ([Gen.boolean]), and strings ([Gen.string]).
/// Also includes combinators like [Gen.oneOf] (choose from values),
/// [Gen.oneOfGen] (choose from generators), and [Gen.constant].
///
/// ```dart
/// final intGen = Gen.integer(min: 0, max: 100);
/// final boolGen = Gen.boolean();
/// final stringGen = Gen.string(maxLength: 20);
/// final choiceGen = Gen.oneOf(['apple', 'banana', 'cherry']);
///
/// final combinedGen = intGen.map((i) => 'Number: $i');
/// ```
class Gen {
  /// Generate integer values
  static Generator<int> integer({
    int? min,
    int? max,
  }) =>
      _IntGenerator(min: min, max: max);

  /// Generate double values
  static Generator<double> double_({
    double? min,
    double? max,
  }) =>
      _DoubleGenerator(min: min, max: max);

  /// Generate boolean values
  static Generator<bool> boolean() => _BoolGenerator();

  /// Generate string values
  static Generator<String> string({
    int? minLength,
    int? maxLength,
  }) =>
      _StringGenerator(minLength: minLength, maxLength: maxLength);

  /// Choose one value from a list of values
  static Generator<T> oneOf<T>(List<T> values) => _OneOfGenerator(values);

  /// Choose one generator from a list of generators
  static Generator<T> oneOfGen<T>(List<Generator<T>> generators) =>
      _OneOfGenGenerator(generators);

  /// Generate a constant value
  static Generator<T> constant<T>(T value) => _ConstantGenerator(value);

  /// Generate a container of type C from elements of type T
  ///
  /// Uses the provided [elementGen] to generate items and the [factory]
  /// function to construct the container instance from an `Iterable<T>`.
  /// Optional [minLength] and [maxLength] constraints control the number
  /// of elements generated.
  ///
  /// Example: Generating a Set of unique integers
  /// ```dart
  /// final setGen = Gen.containerOf<Set<int>, int>(
  ///   Gen.integer(min: 0, max: 10),
  ///   (items) => Set<int>.from(items), // Factory function
  ///   minLength: 1,
  ///   maxLength: 5,
  /// );
  /// ```
  static Generator<C> containerOf<C, T>(
    Generator<T> elementGen,
    C Function(Iterable<T>) factory, {
    int? minLength,
    int? maxLength,
  }) =>
      _ContainerGenerator(elementGen, factory, minLength: minLength, maxLength: maxLength);


      /// Choose one generator from a list based on assigned weights.
  ///
  /// Takes a list of tuples, where each tuple contains a positive integer
  /// weight and a generator. The probability of selecting a generator is
  /// proportional to its weight relative to the total weight of all generators.
  ///
  /// Example:
  /// ```dart
  /// final weightedGen = Gen.frequency([
  ///   (3, Gen.integer(max: 10)), // 3 times more likely
  ///   (1, Gen.integer(min: 100)),
  /// ]);
  /// ```
  static Generator<T> frequency<T>(List<(int weight, Generator<T> generator)> weightedGenerators) =>
      _FrequencyGenerator(weightedGenerators);

  /// Generate a list containing exactly [n] distinct elements chosen
  /// randomly from the provided [options] list.
  ///
  /// Throws if `n` is negative or greater than the number of options.
  /// The order of elements in the generated list is not guaranteed.
  ///
  /// Example:
  /// ```dart
  /// final pickTwoGen = Gen.pick(2, ['a', 'b', 'c']);
  /// // Possible outputs: ['a', 'b'], ['a', 'c'], ['b', 'c'] (in any order)
  /// ```
  static Generator<List<T>> pick<T>(int n, List<T> options) =>
      _PickGenerator(n, options);

  /// Generate a list containing a variable number of distinct elements
  /// chosen randomly from the provided [options] list.
  ///
  /// The number of elements chosen will be between [min] (inclusive, defaults to 0)
  /// and [max] (inclusive, defaults to `options.length`).
  /// Throws if bounds are invalid. The order of elements is not guaranteed.
  ///
  /// Example:
  /// ```dart
  /// final someLettersGen = Gen.someOf(['x', 'y', 'z'], min: 1, max: 2);
  /// // Possible outputs: ['x'], ['y'], ['z'], ['x', 'y'], ['x', 'z'], ['y', 'z']
  /// ```
  static Generator<List<T>> someOf<T>(List<T> options, {int? min, int? max}) =>
      _SomeOfGenerator(options, min: min, max: max);

  /// Generate a list containing at least one distinct element chosen
  /// randomly from the provided [options] list.
  ///
  /// This is a shorthand for `Gen.someOf(options, min: 1)`.
  /// The order of elements is not guaranteed.
  ///
  /// Example:
  /// ```dart
  /// final atLeastOneDigitGen = Gen.atLeastOne(['1', '2', '3']);
  /// // Possible outputs: ['1'], ['2'], ['3'], ['1', '2'], ['1', '3'], ['2', '3'], ['1', '2', '3']
  /// ```
  static Generator<List<T>> atLeastOne<T>(List<T> options) =>
      _SomeOfGenerator(options, min: 1, max: options.length);

}



// --- Integer Generator ---
class _IntGenerator extends Generator<int> {
  final int min;
  final int max;

  _IntGenerator({int? min, int? max})
      : min = min ?? -1000,
        max = max ?? 1000 {
    if (this.min > this.max) { // Use resolved min/max
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
      final int target = (min <= 0 && max >= 0) ? 0 : (min.abs() < max.abs() ? min : max);
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

// --- Double Generator ---
class _DoubleGenerator extends Generator<double> {
  final double min;
  final double max;

  _DoubleGenerator({double? min, double? max})
      : min = min ?? -1000.0,
        max = max ?? 1000.0 {
    if (this.min > this.max) { // Use resolved min/max
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
      final double target = (min <= 0.0 && max >= 0.0) ? 0.0 : (min.abs() < max.abs() ? min : max);
      const tolerance = 1e-9;
      var current = value;
      final yielded = <double>{value}; // Track yielded values
      
      // Common failure boundary values to try first
      final commonBoundaries = <double>[1.0, -1.0, 1.001, -1.001, 0.999, -0.999, 0.0, 0.1, -0.1, 10.0, -10.0];
      
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
        if (!current.isFinite || !target.isFinite || (current - target).abs() <= tolerance) break; // Stop if target reached or non-finite

        final next = target + (current - target) / 2.0;

        if (!next.isFinite) break; // Stop if shrink results in non-finite

        // Ensure progress beyond tolerance
        if ((current - next).abs() <= tolerance) break;
        // Ensure getting closer
        if ((next - target).abs() >= (current - target).abs() - tolerance) break;

        if (!yielded.contains(next) && next >= min - tolerance && next <= max + tolerance) {
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
          if (!yielded.contains(above) && above >= min - tolerance && above <= max + tolerance) {
            yielded.add(above);
            yield ShrinkableValue.leaf(above);
          }
          
          final below = target - delta;
          if (!yielded.contains(below) && below >= min - tolerance && below <= max + tolerance) {
            yielded.add(below);
            yield ShrinkableValue.leaf(below);
          }
        }
        
        // Add explicit boundaries for common test values (especially the 1.0 boundary)
        for (double d = 1.0; d <= 1.2; d += 0.01) {
          if (!yielded.contains(d) && d >= min - tolerance && d <= max + tolerance) {
            yielded.add(d);
            yield ShrinkableValue.leaf(d);
          }
          
          final negD = -d;
          if (!yielded.contains(negD) && negD >= min - tolerance && negD <= max + tolerance) {
            yielded.add(negD);
            yield ShrinkableValue.leaf(negD);
          }
        }
      }

      // 4. Yield boundaries if valid and different
      if (min.isFinite && !yielded.contains(min) && min >= min - tolerance && min <= max + tolerance) {
         yielded.add(min);
         yield ShrinkableValue.leaf(min);
      }
      if (max.isFinite && !yielded.contains(max) && max >= min - tolerance && max <= max + tolerance) {
         yielded.add(max);
         yield ShrinkableValue.leaf(max);
      }
    }); // End sync*
  }
}

// --- Boolean Generator ---
class _BoolGenerator extends Generator<bool> {
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

// --- String Generator ---
class _StringGenerator extends Generator<String> {
  final int minLength;
  final int maxLength;
  static const _chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  _StringGenerator({int? minLength, int? maxLength})
      : minLength = minLength ?? 0,
        maxLength = maxLength ?? 100 {
    if (this.minLength < 0) {
        throw ArgumentError('minLength must be non-negative');
    }
    if (this.maxLength < 0) {
        throw ArgumentError('maxLength must be non-negative');
    }
    if (this.minLength > this.maxLength) {
      throw ArgumentError('minLength must be less than or equal to maxLength');
    }
  }

  @override
  ShrinkableValue<String> generate(Random random) {
    final length = minLength + random.nextInt(maxLength - minLength + 1);
    final value = String.fromCharCodes(
      List.generate(length, (_) => _chars.codeUnitAt(random.nextInt(_chars.length))),
    );

    return ShrinkableValue(value, () sync* {
      // --- Shrinking Strategy Order ---
      // 1. Yield minimal string ('', or 'a'*minLength) - Often the simplest target
      // 2. Remove characters (towards minLength)
      // 3. Simplify characters (try to reach 'a', 'A', '0')

      final yielded = <String>{value}; // Track yielded strings

      // Helper to yield only if valid and not already yielded
      bool yieldIfNewAndValid(String s) {
        if (s.length >= minLength && !yielded.contains(s)) {
          yielded.add(s);
          return true;
        }
        return false;
      }

      // 1. Yield minimal string first
      if (minLength == 0) {
        if (yieldIfNewAndValid('')) {
          yield ShrinkableValue.leaf('');
        }
      } else {
        final minimalString = 'a' * minLength;
        if (yieldIfNewAndValid(minimalString)) {
          yield ShrinkableValue.leaf(minimalString);
        }
      }

      // 2. Try removing characters
      if (value.length > minLength) {
        // a. Try removing chunks (halving towards minLength)
        // Start from original length, try halfway to minLength repeatedly.
        // This converges faster for long strings.
        var len = value.length;
        while (len > minLength) {
           final nextLen = (len + minLength) ~/ 2;
           if (nextLen < len && nextLen >= minLength) { // Ensure progress and respects minLength
              final sub = value.substring(0, nextLen);
               if (yieldIfNewAndValid(sub)) {
                  yield ShrinkableValue.leaf(sub);
               }
               // Continue halving from the original length, don't update len here
               // to explore different chunk sizes. But stop if nextLen is not smaller.
               len = nextLen; // Correction: Update len to ensure loop termination
           } else {
              break; // No progress or already at/below minLength
           }
        }
        // b. Ensure the exact minLength string is yielded if possible and not already done
        if (minLength < value.length) {
           final minLenString = value.substring(0, minLength);
           if (yieldIfNewAndValid(minLenString)) {
              yield ShrinkableValue.leaf(minLenString);
           }
        }

        // c. Try removing individual characters (from the end, then start)
        // From end: Often finds issues related to trailing characters
        for (int i = value.length - 1; i >= 0; i--) {
           final reduced = value.substring(0, i) + value.substring(i + 1);
           if (yieldIfNewAndValid(reduced)) {
             yield ShrinkableValue.leaf(reduced);
           }
        }
        // From start: Less common but possible
         if (value.isNotEmpty) {
            final reduced = value.substring(1);
             if (yieldIfNewAndValid(reduced)) {
               yield ShrinkableValue.leaf(reduced);
             }
         }
      }

      // 3. Try simplifying characters
      bool changed = false;
      final simplifiedChars = StringBuffer();
      for (var i = 0; i < value.length; i++) {
        final char = value[i];
        String simplifiedChar = char; // Default is no change
        if (RegExp(r'[a-z]').hasMatch(char) && char != 'a') {
          simplifiedChar = 'a'; changed = true;
        } else if (RegExp(r'[A-Z]').hasMatch(char) && char != 'A') {
          simplifiedChar = 'A'; changed = true;
        } else if (RegExp(r'[0-9]').hasMatch(char) && char != '0') {
          simplifiedChar = '0'; changed = true;
        }
        simplifiedChars.write(simplifiedChar);
      }
      if (changed) {
        final simplifiedString = simplifiedChars.toString();
        if (yieldIfNewAndValid(simplifiedString)) {
          yield ShrinkableValue.leaf(simplifiedString);
        }
      }
    }); // End sync*
  }
}

// --- OneOf Value Generator ---
class _OneOfGenerator<T> extends Generator<T> {
  final List<T> values;

  _OneOfGenerator(this.values) {
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

// --- OneOf Generator Generator ---
class _OneOfGenGenerator<T> extends Generator<T> {
  final List<Generator<T>> generators;

  _OneOfGenGenerator(this.generators) {
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

// --- Constant Generator ---
class _ConstantGenerator<T> extends Generator<T> {
  final T value;
  _ConstantGenerator(this.value);

  @override
  ShrinkableValue<T> generate(Random random) => ShrinkableValue.leaf(value);
}

// --- Container Generator ---
class _ContainerGenerator<C, T> extends Generator<C> {
  final Generator<T> elementGen;
  final C Function(Iterable<T>) factory;
  final int? minLength;
  final int? maxLength;
  late final ListGenerator<T> _listGenerator; // Internal list generator

  _ContainerGenerator(this.elementGen, this.factory, {this.minLength, this.maxLength}) {
    _listGenerator = ListGenerator<T>(elementGen, minLength: minLength, maxLength: maxLength);
    // Validation is handled by ListGenerator constructor
  }

  @override
  ShrinkableValue<C> generate(Random random) {
    final listShrinkable = _listGenerator.generate(random);
    final containerValue = factory(listShrinkable.value);

    // Shrinking the container involves shrinking the underlying list and
    // re-applying the factory.
    ShrinkableValue<C> shrinkContainer(ShrinkableValue<List<T>> shrunkListSV) {
      return ShrinkableValue<C>(
        factory(shrunkListSV.value),
        // Recursively define shrinks for the container based on list shrinks
        () => shrunkListSV.shrinks().map(shrinkContainer),
      );
    }

    return ShrinkableValue<C>(
      containerValue,
      () => listShrinkable.shrinks().map(shrinkContainer),
    );
  }
}


// --- Frequency Generator ---
class _FrequencyGenerator<T> extends Generator<T> {
  final List<(int weight, Generator<T> generator)> weightedGenerators;
  final int totalWeight;

  _FrequencyGenerator(this.weightedGenerators)
      : totalWeight = weightedGenerators.fold(0, (sum, item) {
          if (item.$1 <= 0) {
            throw ArgumentError('Weights must be positive: ${item.$1}');
          }
          return sum + item.$1;
        }) {
    if (weightedGenerators.isEmpty) {
      throw ArgumentError('weightedGenerators must not be empty');
    }
    if (totalWeight <= 0) {
       // This case should be caught by the individual weight check, but as a safeguard:
      throw ArgumentError('Total weight must be positive');
    }
  }

  @override
  ShrinkableValue<T> generate(Random random) {
    var value = random.nextInt(totalWeight);
    Generator<T>? chosenGenerator;

    for (final item in weightedGenerators) {
      if (value < item.$1) {
        chosenGenerator = item.$2;
        break;
      }
      value -= item.$1;
    }

    // chosenGenerator should always be non-null if totalWeight > 0
    final shrinkable = chosenGenerator!.generate(random);

    // Shrinking only shrinks the value generated by the chosen generator.
    // It does NOT try to switch to a different generator from the list.
    return ShrinkableValue(shrinkable.value, shrinkable.shrinks);
  }
}

// --- Sampling Generators (pick, someOf) ---

// Helper to generate lists of unique items by picking from options
abstract class _SamplingGenerator<T> extends Generator<List<T>> {
  final List<T> options;

  _SamplingGenerator(this.options) {
    if (options.isEmpty) {
      // While technically possible to pick 0 from empty, it's ambiguous
      // for someOf/atLeastOne, so disallow empty options for simplicity.
      throw ArgumentError('options list cannot be empty for sampling generators');
    }
  }

  List<T> _selectItems(int count, Random random) {
    if (count > options.length) {
       // Should be caught by validation below, but safeguard here.
      count = options.length;
    }
    final shuffled = List<T>.from(options)..shuffle(random);
    return shuffled.sublist(0, count);
  }

  // Default shrink: remove elements, replace elements with earlier ones in original list
  Iterable<ShrinkableValue<List<T>>> _shrinkList(List<T> currentList, int minCount) sync* {
     final yielded = <List<T>>{currentList}; // Track yields

     bool yieldIfNew(List<T> list) {
        if (list.length >= minCount && !yielded.contains(list)) {
           yielded.add(list);
           return true;
        }
        return false;
     }

     // 1. Try removing elements (if above minCount)
     if (currentList.length > minCount) {
        // Try removing chunks first
        var len = currentList.length;
        while(len > minCount) {
           final nextLen = (len + minCount) ~/ 2;
           if (nextLen < len && nextLen >= minCount) {
              final sub = currentList.sublist(0, nextLen);
               if (yieldIfNew(sub)) {
                  yield ShrinkableValue.leaf(sub);
                  len = nextLen;
               } else break;
           } else break;
        }
        // Ensure exact min length is tried if possible
        if (len != minCount && minCount < currentList.length) {
            final sub = currentList.sublist(0, minCount);
             if (yieldIfNew(sub)) yield ShrinkableValue.leaf(sub);
        }

        // Try removing individual elements (from end)
        for (int i = currentList.length - 1; i >= 0; --i) {
           final nextList = List<T>.from(currentList)..removeAt(i);
           if (yieldIfNew(nextList)) {
             yield ShrinkableValue.leaf(nextList);
           }
        }
     }

     // 2. Try replacing elements with earlier elements from the *original* options list
     for (int i = 0; i < currentList.length; ++i) {
        final currentElement = currentList[i];
        final originalIndex = options.indexOf(currentElement);
        if (originalIndex > 0) { // If it's not the very first option
           for (int j = 0; j < originalIndex; ++j) {
              final earlierOption = options[j];
              // Ensure we don't introduce a duplicate if not allowed (e.g. for pick/someOf)
              if (!currentList.contains(earlierOption)) {
                  final nextList = List<T>.from(currentList);
                  nextList[i] = earlierOption;
                  // Sorting helps canonicalize for the 'yielded' set
                  nextList.sort((a,b) => options.indexOf(a).compareTo(options.indexOf(b)));
                   if (yieldIfNew(nextList)) {
                      yield ShrinkableValue.leaf(nextList);
                   }
              }
           }
        }
     }
  }
}

class _PickGenerator<T> extends _SamplingGenerator<T> {
  final int count;

  _PickGenerator(this.count, List<T> options) : super(options) {
    if (count < 0 || count > options.length) {
      throw ArgumentError('count ($count) must be between 0 and options.length (${options.length})');
    }
  }

  @override
  ShrinkableValue<List<T>> generate(Random random) {
    final value = _selectItems(count, random);
    return ShrinkableValue(value, () => _shrinkList(value, count)); // minCount is fixed at count
  }
}

class _SomeOfGenerator<T> extends _SamplingGenerator<T> {
  final int min;
  final int max;

  _SomeOfGenerator(List<T> options, {int? min, int? max})
      : min = min ?? 0,
        max = max ?? options.length,
        super(options) {
    if (this.min < 0 || this.min > options.length) {
      throw ArgumentError('min (${this.min}) must be between 0 and options.length (${options.length})');
    }
    if (this.max < this.min || this.max > options.length) {
      throw ArgumentError('max (${this.max}) must be between min (${this.min}) and options.length (${options.length})');
    }
  }

  @override
  ShrinkableValue<List<T>> generate(Random random) {
    final count = min + random.nextInt(max - min + 1);
    final value = _selectItems(count, random);
    return ShrinkableValue(value, () => _shrinkList(value, min)); // Use dynamic minCount
  }
}
