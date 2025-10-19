import 'dart:math' show Random;

import '../../generator_base.dart';

/// A generator for string values with shrinking capabilities.
class StringGenerator extends Generator<String> {
  final int minLength;
  final int maxLength;
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  StringGenerator({int? minLength, int? maxLength})
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
      List.generate(
        length,
        (_) => _chars.codeUnitAt(random.nextInt(_chars.length)),
      ),
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
          if (nextLen < len && nextLen >= minLength) {
            // Ensure progress and respects minLength
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
          simplifiedChar = 'a';
          changed = true;
        } else if (RegExp(r'[A-Z]').hasMatch(char) && char != 'A') {
          simplifiedChar = 'A';
          changed = true;
        } else if (RegExp(r'[0-9]').hasMatch(char) && char != '0') {
          simplifiedChar = '0';
          changed = true;
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
