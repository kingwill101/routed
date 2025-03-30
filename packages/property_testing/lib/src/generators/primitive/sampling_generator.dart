import 'dart:math' show Random;

import '../../generator_base.dart';

/// Base class for generators that sample unique elements from a list of options.
abstract class SamplingGenerator<T> extends Generator<List<T>> {
  final List<T> options;

  SamplingGenerator(this.options) {
    if (options.isEmpty) {
      // While technically possible to pick 0 from empty, it's ambiguous
      // for someOf/atLeastOne, so disallow empty options for simplicity.
      throw ArgumentError(
          'options list cannot be empty for sampling generators');
    }
  }

  /// Selects [count] unique items from the options list.
  List<T> selectItems(int count, Random random) {
    if (count > options.length) {
      // Should be caught by validation below, but safeguard here.
      count = options.length;
    }
    final shuffled = List<T>.from(options)..shuffle(random);
    return shuffled.sublist(0, count);
  }

  /// Shrinks a list by removing elements or replacing with earlier elements from options.
  Iterable<ShrinkableValue<List<T>>> shrinkList(
      List<T> currentList, int minCount) sync* {
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
      while (len > minCount) {
        final nextLen = (len + minCount) ~/ 2;
        if (nextLen < len && nextLen >= minCount) {
          final sub = currentList.sublist(0, nextLen);
          if (yieldIfNew(sub)) {
            yield ShrinkableValue.leaf(sub);
            len = nextLen;
          } else {
            break;
          }
        } else {
          break;
        }
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
      if (originalIndex > 0) {
        // If it's not the very first option
        for (int j = 0; j < originalIndex; ++j) {
          final earlierOption = options[j];
          // Ensure we don't introduce a duplicate if not allowed (e.g. for pick/someOf)
          if (!currentList.contains(earlierOption)) {
            final nextList = List<T>.from(currentList);
            nextList[i] = earlierOption;
            // Sorting helps canonicalize for the 'yielded' set
            nextList.sort(
                (a, b) => options.indexOf(a).compareTo(options.indexOf(b)));
            if (yieldIfNew(nextList)) {
              yield ShrinkableValue.leaf(nextList);
            }
          }
        }
      }
    }
  }
}
