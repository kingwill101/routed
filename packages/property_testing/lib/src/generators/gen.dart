import '../generator_base.dart';
import 'primitive/bool_generator.dart';
import 'primitive/constant_generator.dart';
import 'primitive/container_generator.dart';
import 'primitive/double_generator.dart';
import 'primitive/frequency_generator.dart';
import 'primitive/int_generator.dart';
import 'primitive/one_of_gen_generator.dart';
import 'primitive/one_of_generator.dart';
import 'primitive/pick_generator.dart';
import 'primitive/some_of_generator.dart';
import 'primitive/string_generator.dart';

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
      IntGenerator(min: min, max: max);

  /// Generate double values
  static Generator<double> double_({
    double? min,
    double? max,
  }) =>
      DoubleGenerator(min: min, max: max);

  /// Generate boolean values
  static Generator<bool> boolean() => BoolGenerator();

  /// Generate string values
  static Generator<String> string({
    int? minLength,
    int? maxLength,
  }) =>
      StringGenerator(minLength: minLength, maxLength: maxLength);

  /// Choose one value from a list of values
  static Generator<T> oneOf<T>(List<T> values) => OneOfGenerator(values);

  /// Choose one generator from a list of generators
  static Generator<T> oneOfGen<T>(List<Generator<T>> generators) =>
      OneOfGenGenerator(generators);

  /// Generate a constant value
  static Generator<T> constant<T>(T value) => ConstantGenerator(value);

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
      ContainerGenerator(elementGen, factory,
          minLength: minLength, maxLength: maxLength);

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
  static Generator<T> frequency<T>(
          List<(int weight, Generator<T> generator)> weightedGenerators) =>
      FrequencyGenerator(weightedGenerators);

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
      PickGenerator(n, options);

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
      SomeOfGenerator(options, min: min, max: max);

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
      SomeOfGenerator(options, min: 1, max: options.length);
}
