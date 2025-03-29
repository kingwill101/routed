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
}

class _IntGenerator extends Generator<int> {
  final int min;
  final int max;

  _IntGenerator({
    int? min,
    int? max,
  })  : min = min ?? -1000,
        max = max ?? 1000;

  @override
  ShrinkableValue<int> generate([Random? random]) {
    final rng = random ?? Random(42);
    final range = max - min + 1;
    final value = min + rng.nextInt(range);

    return ShrinkableValue(value, () sync* {
      var current = value;
      while (current != 0 && current > min) {
        current ~/= 2;
        if (current >= min) {
          yield ShrinkableValue.leaf(current);
        }
      }
    });
  }
}

class _DoubleGenerator extends Generator<double> {
  final double min;
  final double max;

  _DoubleGenerator({
    double? min,
    double? max,
  })  : min = min ?? -1000.0,
        max = max ?? 1000.0;

  @override
  ShrinkableValue<double> generate([Random? random]) {
    final rng = random ?? Random(42);
    final value = min + rng.nextDouble() * (max - min);

    return ShrinkableValue(value, () sync* {
      var current = value;
      while (current != 0.0 && current > min) {
        current /= 2;
        if (current >= min) {
          yield ShrinkableValue.leaf(current);
        }
      }
    });
  }
}

class _BoolGenerator extends Generator<bool> {
  @override
  ShrinkableValue<bool> generate([Random? random]) {
    final rng = random ?? Random(42);
    final value = rng.nextBool();

    return ShrinkableValue(value, () sync* {
      if (value) {
        yield ShrinkableValue.leaf(false);
      }
    });
  }
}

class _StringGenerator extends Generator<String> {
  final int minLength;
  final int maxLength;
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  _StringGenerator({
    int? minLength,
    int? maxLength,
  })  : minLength = minLength ?? 0,
        maxLength = maxLength ?? 100;

  @override
  ShrinkableValue<String> generate([Random? random]) {
    final rng = random ?? Random(42);
    final length = minLength + rng.nextInt(maxLength - minLength + 1);
    final value = String.fromCharCodes(
      List.generate(
          length, (_) => _chars.codeUnitAt(rng.nextInt(_chars.length))),
    );

    return ShrinkableValue(value, () sync* {
      // Try removing characters
      if (value.length > minLength) {
        for (var i = 0; i < value.length; i++) {
          final shortened = value.substring(0, i) + value.substring(i + 1);
          if (shortened.length >= minLength) {
            yield ShrinkableValue.leaf(shortened);
          }
        }
      }

      // Try simplifying characters
      for (var i = 0; i < value.length; i++) {
        final char = value[i];
        if (char.toUpperCase() != char) {
          yield ShrinkableValue.leaf(
            value.substring(0, i) + char.toUpperCase() + value.substring(i + 1),
          );
        }
      }
    });
  }
}

class _OneOfGenerator<T> extends Generator<T> {
  final List<T> values;

  _OneOfGenerator(this.values) {
    if (values.isEmpty) {
      throw ArgumentError('values must not be empty');
    }
  }

  @override
  ShrinkableValue<T> generate([Random? random]) {
    final rng = random ?? Random(42);
    final value = values[rng.nextInt(values.length)];

    return ShrinkableValue(value, () sync* {
      // Try values earlier in the list
      final index = values.indexOf(value);
      for (var i = 0; i < index; i++) {
        yield ShrinkableValue.leaf(values[i]);
      }
    });
  }
}

class _OneOfGenGenerator<T> extends Generator<T> {
  final List<Generator<T>> generators;

  _OneOfGenGenerator(this.generators) {
    if (generators.isEmpty) {
      throw ArgumentError('generators must not be empty');
    }
  }

  @override
  ShrinkableValue<T> generate([Random? random]) {
    final rng = random ?? Random(42);
    final generator = generators[rng.nextInt(generators.length)];
    final value = generator.generate(random);

    return ShrinkableValue(value.value, () sync* {
      // Try values from generators earlier in the list
      final index = generators.indexOf(generator);
      for (var i = 0; i < index; i++) {
        yield generators[i].generate(random);
      }

      // Try shrinking the chosen value
      yield* value.shrinks();
    });
  }
}

class _ConstantGenerator<T> extends Generator<T> {
  final T value;

  _ConstantGenerator(this.value);

  @override
  ShrinkableValue<T> generate([Random? random]) => ShrinkableValue.leaf(value);
}
