import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator that produces lists of values from another generator.
///
/// The resulting lists have lengths between [minLength] and [maxLength] inclusive.
/// Shrinking tries to remove elements or shrink individual elements.
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
  ShrinkableValue<List<T>> generate(Random random) {
    final length = _generateLength(random);
    // Pass the same random instance to element generators
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