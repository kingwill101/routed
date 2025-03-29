import 'dart:math' show Random;

/// Base class for all generators in the property testing framework.
/// The base class for all value generators in the property testing framework.
///
/// A generator is responsible for creating [ShrinkableValue] instances of type
/// [T]. These values are used as inputs for property tests. Generators also
/// define how values can be combined or transformed using methods like [map],
/// [flatMap], [where], and [list].
///
/// ```dart
/// // Example: Creating a generator for positive integers
/// final positiveIntGenerator = Gen.integer().where((n) => n > 0);
///
/// // Example: Creating a generator for user IDs (strings) from integers
/// final userIdGenerator = Gen.integer(min: 1).map((id) => 'user_$id');
/// ```
abstract class Generator<T> {
  /// Generate a shrinkable value of type T
  ShrinkableValue<T> generate([Random? random]);

  /// Map this generator to a new type using a transformation function
  Generator<R> map<R>(R Function(T value) f) => MappedGenerator(this, f);

  /// FlatMap this generator to create a new generator based on the current value
  Generator<R> flatMap<R>(Generator<R> Function(T value) f) =>
      FlatMappedGenerator(this, f);

  /// Filter values from this generator based on a predicate
  Generator<T> where(bool Function(T value) predicate) =>
      FilteredGenerator(this, predicate);

  /// Create a new generator that produces lists of values from this generator
  Generator<List<T>> list({int? minLength, int? maxLength}) =>
      ListGenerator(this, minLength: minLength, maxLength: maxLength);
}

/// A value that can be shrunk to simpler values
/// Represents a generated value along with the logic for shrinking it.
///
/// Shrinking is the process of simplifying a failing test case input to find
/// the smallest possible example that still causes the failure. This makes
/// debugging easier.
///
/// The [value] property holds the actual generated data, while the [shrinks]
/// method provides an iterable of potentially simpler [ShrinkableValue]s.
///
/// ```dart
/// final shrinkableInt = Gen.integer().generate();
/// print('Generated value: ${shrinkableInt.value}');
///
/// // Get potential shrinks
/// for (final shrunkValue in shrinkableInt.shrinks()) {
///   print('Shrunk value: ${shrunkValue.value}');
/// }
/// ```
class ShrinkableValue<T> {
  final T value;
  final Iterable<ShrinkableValue<T>> Function() _shrinks;

  ShrinkableValue(this.value, this._shrinks);

  /// Get the possible shrinks of this value
  Iterable<ShrinkableValue<T>> shrinks() => _shrinks();

  /// Create a shrinkable value with no shrinks
  static ShrinkableValue<T> leaf<T>(T value) =>
      ShrinkableValue(value, () => const []);
}

/// A generator that maps values from one type to another
/// A generator that transforms values produced by a source generator.
///
/// It takes a `source` generator of type [T] and a function `f` that converts
/// values of type [T] to type [R]. The resulting generator produces values
/// of type [R]. Shrinking is delegated to the source generator, and the
/// transformation function is applied to the shrunk values.
///
/// Typically created using [Generator.map].
///
/// ```dart
/// final stringLengthGen = Gen.string().map((s) => s.length);
/// ```
class MappedGenerator<T, R> extends Generator<R> {
  final Generator<T> source;
  final R Function(T) f;

  MappedGenerator(this.source, this.f);

  @override
  ShrinkableValue<R> generate([Random? random]) {
    final sourceValue = source.generate(random);
    return ShrinkableValue(
      f(sourceValue.value),
      () => sourceValue
          .shrinks()
          .map((s) => ShrinkableValue(f(s.value), () => [])),
    );
  }
}

/// A generator that uses the output of one generator to create another
/// A generator that creates a new generator based on the value of a source generator.
///
/// This allows for dependent generators, where the generation of the next value
/// depends on the previously generated value. It takes a `source` generator of
/// type [T] and a function `f` that takes a value of type [T] and returns a
/// new `Generator<R>`.
///
/// Shrinking attempts to shrink both the source value and the resulting value.
///
/// Typically created using [Generator.flatMap].
///
/// ```dart
/// final dependentGen = Gen.integer(min: 1, max: 10).flatMap((count) {
///   return Gen.string(maxLength: count); // String length depends on integer
/// });
/// ```
class FlatMappedGenerator<T, R> extends Generator<R> {
  final Generator<T> source;
  final Generator<R> Function(T) f;

  FlatMappedGenerator(this.source, this.f);

  @override
  ShrinkableValue<R> generate([Random? random]) {
    final sourceValue = source.generate(random);
    final resultGen = f(sourceValue.value);
    final resultValue = resultGen.generate(random);

    return ShrinkableValue(
      resultValue.value,
      () sync* {
        // Try shrinking the source value
        for (final shrunkSource in sourceValue.shrinks()) {
          final shrunkGen = f(shrunkSource.value);
          yield shrunkGen.generate(random);
        }
        // Try shrinking the result value
        yield* resultValue.shrinks();
      },
    );
  }
}

/// A generator that filters values based on a predicate
/// A generator that filters values produced by a source generator based on a predicate.
///
/// It takes a `source` generator and a `predicate` function. Only values from
/// the source generator for which the predicate returns `true` are produced.
/// If the predicate rejects too many values consecutively, an exception is thrown.
///
/// Shrinking only considers shrunk values that also satisfy the predicate.
///
/// Typically created using [Generator.where].
///
/// ```dart
/// final evenIntGen = Gen.integer().where((n) => n.isEven);
/// ```
class FilteredGenerator<T> extends Generator<T> {
  final Generator<T> source;
  final bool Function(T) predicate;
  static const _maxAttempts = 100;

  FilteredGenerator(this.source, this.predicate);

  @override
  ShrinkableValue<T> generate([Random? random]) {
    for (var i = 0; i < _maxAttempts; i++) {
      final value = source.generate(random);
      if (predicate(value.value)) {
        return ShrinkableValue(
          value.value,
          () => value.shrinks().where((s) => predicate(s.value)),
        );
      }
    }
    throw Exception(
        'Could not generate value matching predicate after $_maxAttempts attempts');
  }
}

/// A generator that produces lists of values
/// A generator that produces lists of values from an element generator.
///
/// Takes an `elementGen` generator for the list items and optional `minLength`
/// and `maxLength` constraints.
///
/// Shrinking attempts to remove elements from the list (respecting `minLength`)
/// and shrink individual elements within the list.
///
/// Typically created using [Generator.list].
///
/// ```dart
/// final listOfBoolsGen = Gen.boolean().list(minLength: 1, maxLength: 5);
/// ```
class ListGenerator<T> extends Generator<List<T>> {
  final Generator<T> elementGen;
  final int? minLength;
  final int? maxLength;

  ListGenerator(this.elementGen, {this.minLength, this.maxLength}) {
    if (minLength != null && maxLength != null && minLength! > maxLength!) {
      throw ArgumentError('minLength must be less than or equal to maxLength');
    }
    if (minLength != null && minLength! < 0) {
      throw ArgumentError('minLength must be non-negative');
    }
    if (maxLength != null && maxLength! < 0) {
      throw ArgumentError('maxLength must be non-negative');
    }
  }

  @override
  ShrinkableValue<List<T>> generate([Random? random]) {
    final rng = random ?? Random(42);
    final length = _generateLength(rng);
    final elements = List.generate(length, (_) => elementGen.generate(random));

    return ShrinkableValue(
      elements.map((e) => e.value).toList(),
      () sync* {
        // Try removing elements (if above minLength)
        if (minLength == null || elements.length > minLength!) {
          for (var i = 0; i < elements.length; i++) {
            final shortened = List<T>.from(elements.map((e) => e.value));
            shortened.removeAt(i);
            yield ShrinkableValue.leaf(shortened);
          }
        }

        // Try shrinking individual elements
        for (var i = 0; i < elements.length; i++) {
          for (final shrunkElement in elements[i].shrinks()) {
            final shrunk = List<T>.from(elements.map((e) => e.value));
            shrunk[i] = shrunkElement.value;
            yield ShrinkableValue.leaf(shrunk);
          }
        }
      },
    );
  }

  int _generateLength(Random random) {
    final min = minLength ?? 0;
    final max = maxLength ?? (min + 10);
    return min + random.nextInt(max - min + 1);
  }
}
