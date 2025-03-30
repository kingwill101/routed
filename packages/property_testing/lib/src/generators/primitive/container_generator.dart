import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator for container types (like List, Set, etc.) using a factory function.
///
/// Uses an element generator to create items and applies a factory function
/// to create the container from the generated elements.
class ContainerGenerator<C, T> extends Generator<C> {
  final Generator<T> elementGen;
  final C Function(Iterable<T>) factory;
  final int? minLength;
  final int? maxLength;
  late final ListGenerator<T> _listGenerator; // Internal list generator

  ContainerGenerator(this.elementGen, this.factory, {this.minLength, this.maxLength}) {
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