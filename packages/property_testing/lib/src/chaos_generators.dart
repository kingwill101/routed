/// Provides generators for creating chaotic and potentially problematic data
/// inputs, useful for robustness and security testing. Includes generators for
/// chaotic strings, integers, JSON, and byte sequences, mimicking common attack
/// vectors and edge cases.
library;

import 'dart:convert';
import 'dart:math' show Random;

import 'generator_base.dart';

/// Categories of chaotic data
/// Defines different categories of chaotic data that generators can produce.
/// Used primarily for configuring the `_ChaoticStringGenerator`.
enum ChaosCategory {
  /// SQL injection attempts
  sqlInjection,

  /// Cross-site scripting attempts
  xss,

  /// Path traversal attempts
  pathTraversal,

  /// Command injection attempts
  commandInjection,

  /// Unicode edge cases
  unicode,

  /// Large inputs
  large,

  /// Special characters
  special,

  /// Format strings
  format,

  /// Null bytes and control characters
  control,

  /// JSON edge cases
  json,
}

/// Configuration for chaos generators
/// Configuration for chaos generators, primarily the string generator.
///
/// Allows customizing the types of chaotic data included ([categories]),
/// the maximum length of generated strings ([maxLength]), and the likelihood
/// ([intensity]) of including chaotic elements versus random characters.
///
/// Example:
/// ```dart
/// // Generate mostly SQL injection and Unicode chaos, up to 500 chars long
/// final config = ChaosConfig(
///   categories: {ChaosCategory.sqlInjection, ChaosCategory.unicode},
///   maxLength: 500,
///   intensity: 0.8, // 80% chance to pick a chaos element
/// );
/// final chaosStringGen = Chaos.string(config: config); // Pass config if generator supports it
/// ```

class ChaosConfig {
  /// The categories of chaos to include
  /// The categories of chaos to potentially include in generated strings.
  /// Defaults to a broad set including SQLi, XSS, path traversal, etc.
  final Set<ChaosCategory> categories;

  /// The maximum length for generated strings
  /// The maximum length (typically in runes/code points for strings) for
  /// generated chaotic data. Defaults to 1000.
  final int maxLength;

  /// The probability of including each type of chaos (0.0 to 1.0)
  /// The probability (0.0 to 1.0) that a generated element (e.g., a character
  /// in a string) will be a "chaotic" one (like a control character or part
  /// of an attack pattern) rather than a standard random character.
  /// Defaults to 0.5.
  final double intensity;

  /// Creates a configuration for chaos generators.
  const ChaosConfig({
    this.categories = const {
      ChaosCategory.sqlInjection,
      ChaosCategory.xss,
      ChaosCategory.pathTraversal,
      ChaosCategory.commandInjection,
      ChaosCategory.unicode,
      ChaosCategory.special,
    },
    this.maxLength = 1000,
    this.intensity = 0.5,
  });
}

/// Provides static factory methods for creating chaos generators.
///
/// These generators produce data designed to stress test systems by including
/// edge cases, potentially malicious inputs, and unusual values. This helps
/// uncover bugs related to input validation, parsing, security, and robustness.
///
/// Example:
/// ```dart
/// test('API handles chaotic user IDs', () async {
///   // Generate chaotic strings up to 50 chars long
///   final chaoticIdGen = Chaos.string(maxLength: 50);
///   final runner = PropertyTestRunner(chaoticIdGen, (userId) async {
///     final response = await client.get('/api/users/$userId');
///     // Ensure the server doesn't crash (500 error)
///     expect(response.statusCode, lessThan(500));
///   });
///   await runner.run();
/// });
/// ```

class Chaos {
  /// Generate chaotic strings
  /// Creates a generator for chaotic strings.
  ///
  /// Produces strings containing a mix of "problematic" characters (like null
  /// bytes, control characters, obscure Unicode characters) and random valid
  /// Unicode code points.
  ///
  /// The [minLength] and [maxLength] primarily control the number of Unicode
  /// code points (runes). The actual `String.length` (UTF-16 code units) might
  /// exceed [maxLength] if multi-unit characters are generated.
  ///
  /// Shrinking attempts to remove characters or replace problematic characters
  /// with spaces while staying within length bounds.

  static Generator<String> string({int? minLength, int? maxLength}) =>
      _ChaoticStringGenerator(minLength: minLength, maxLength: maxLength);

  /// Creates a generator for chaotic integers.
  ///
  /// Produces integers within the optional [min] and [max] bounds. It has a
  /// high probability of generating common integer edge cases (like 0, 1, -1,
  /// min/max int values, max safe JS integer) clamped within the bounds,
  /// as well as random integers within the range.
  ///
  /// Shrinking targets 0 (if in range) or the `min`/`max` boundary, as well
  /// as the included edge cases.

  static Generator<int> integer({int? min, int? max}) =>
      _ChaoticIntGenerator(min: min, max: max);

  /// Creates a generator for chaotic JSON strings.
  ///
  /// Produces strings that are *likely* JSON, but may contain structural errors,
  /// problematic characters within strings, deeply nested structures (up to
  /// [maxDepth]), or large arrays/objects (up to [maxLength] elements/keys
  /// per level).
  ///
  /// This is useful for testing JSON parser robustness.
  ///
  /// Shrinking attempts to simplify the structure (removing keys/elements) and
  /// targets basic valid JSON primitives (`{}`, `[]`, `null`, `""`, `0`, `true`, `false`).
  /// Note: Shrinking might sometimes result in invalid JSON if the original was invalid.

  static Generator<String> json({int maxDepth = 3, int maxLength = 10}) =>
      _ChaoticJsonGenerator(maxDepth: maxDepth, maxLength: maxLength);

  /// Creates a generator for chaotic byte lists (`List<int>`).
  ///
  /// Produces lists of integers (each 0-255) within the optional [minLength]
  /// and [maxLength]. Includes a mix of random bytes and "problematic" bytes
  /// (like 0x00, 0xFF, BOM sequences, control characters).
  ///
  /// Useful for testing binary data parsing or handling.
  ///
  /// Shrinking attempts to remove bytes, replace problematic bytes with 0x00,
  /// and shrink towards the minimum length or an empty list.

  static Generator<List<int>> bytes({int? minLength, int? maxLength}) =>
      _ChaoticBytesGenerator(minLength: minLength, maxLength: maxLength);
}

/// Internal implementation for generating chaotic strings.
class _ChaoticStringGenerator extends Generator<String> {
  final int minLength;
  final int maxLength;

  static const _problematicChars = [
    '\u0000', // Null character
    '\u0001', // Start of heading
    '\u0002', // Start of text
    '\u0003', // End of text
    '\u0004', // End of transmission
    '\u0005', // Enquiry
    '\u0006', // Acknowledge
    '\u0007', // Bell
    '\u0008', // Backspace
    '\u0009', // Horizontal tab
    '\u000A', // Line feed
    '\u000B', // Vertical tab
    '\u000C', // Form feed
    '\u000D', // Carriage return
    '\u000E', // Shift out
    '\u000F', // Shift in
    '\u001F', // Unit separator
    '\u007F', // Delete
    '\u0080', // Padding character
    '\u0081', // High octet preset
    '\u0082', // Break permitted here
    '\u0083', // No break here
    '\u0084', // Index
    '\u0085', // Next line
    '\u0086', // Start of selected area
    '\u0087', // End of selected area
    '\u0088', // Character tabulation set
    '\u0089', // Character tabulation with justification
    '\u008A', // Line tabulation set
    '\u008B', // Partial line forward
    '\u008C', // Partial line backward
    '\u008D', // Reverse line feed
    '\u008E', // Single shift two
    '\u008F', // Single shift three
    '\u0090', // Device control string
    '\u0091', // Private use one
    '\u0092', // Private use two
    '\u0093', // Set transmit state
    '\u0094', // Cancel character
    '\u0095', // Message waiting
    '\u0096', // Start of guarded area
    '\u0097', // End of guarded area
    '\u0098', // Start of string
    '\u0099', // Single graphic character introducer
    '\u009A', // Single character introducer
    '\u009B', // Control sequence introducer
    '\u009C', // String terminator
    '\u009D', // Operating system command
    '\u009E', // Privacy message
    '\u009F', // Application program command
    '\u200B', // Zero width space
    '\u200C', // Zero width non-joiner
    '\u200D', // Zero width joiner
    '\u200E', // Left-to-right mark
    '\u200F', // Right-to-left mark
    '\u2028', // Line separator
    '\u2029', // Paragraph separator
    '\uFEFF', // Byte order mark
    '\uFFFE', // Invalid character
    '\uFFFF', // Invalid character
  ];

  _ChaoticStringGenerator({int? minLength, int? maxLength})
    : minLength = minLength ?? 0,
      maxLength = maxLength ?? 100;

  @override
  ShrinkableValue<String> generate(Random random) {
    final length = minLength + random.nextInt(maxLength - minLength + 1);
    final buffer = StringBuffer();

    for (var i = 0; i < length; i++) {
      if (random.nextBool()) {
        // Use a problematic character
        buffer.write(
          _problematicChars[random.nextInt(_problematicChars.length)],
        );
      } else {
        // Use a random Unicode character
        // Avoid generating surrogate code points which are invalid alone
        int codePoint;
        do {
          codePoint = random.nextInt(0x10FFFF + 1);
        } while (codePoint >= 0xD800 && codePoint <= 0xDFFF);
        buffer.writeCharCode(codePoint);
      }
    }

    final value = buffer.toString();

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

      // Try replacing problematic characters with spaces
      for (var i = 0; i < value.length; i++) {
        if (_problematicChars.contains(value[i])) {
          yield ShrinkableValue.leaf(
            '${value.substring(0, i)} ${value.substring(i + 1)}',
          );
        }
      }
    });
  }
}

/// Internal implementation for generating chaotic integers.
class _ChaoticIntGenerator extends Generator<int> {
  final int min;
  final int max;

  static const _edgeCases = [
    0,
    1,
    -1,
    9007199254740991, // Maximum safe integer in JavaScript
    -9007199254740991, // Minimum safe integer in JavaScript
    2147483647, // Maximum 32-bit signed integer
    -2147483648, // Minimum 32-bit signed integer
    4294967295, // Maximum 32-bit unsigned integer
    9223372036854775807, // Maximum 64-bit signed integer
    -9223372036854775808, // Minimum 64-bit signed integer
  ];

  _ChaoticIntGenerator({int? min, int? max})
    : min = min ?? -9223372036854775808,
      max = max ?? 9223372036854775807;

  @override
  ShrinkableValue<int> generate(Random random) {
    final useProblematic = random.nextBool();

    // Ensure generated value is within bounds
    int value;
    if (useProblematic) {
      value = _edgeCases[random.nextInt(_edgeCases.length)];
      // Clamp problematic value within configured min/max
      if (value < min) value = min;
      if (value > max) value = max;
    } else {
      final range = max - min + 1;
      value = range <= 0 ? min : min + random.nextInt(range);
    }

    return ShrinkableValue(value, () sync* {
      // Try problematic values that are smaller (closer to zero or min)
      for (final problematic in _edgeCases) {
        if (problematic >= min && problematic <= max) {
          // Ensure within bounds
          if ((value > 0 &&
                  problematic < value &&
                  problematic >= 0) || // Shrink positive towards 0
              (value < 0 &&
                  problematic > value &&
                  problematic <= 0) || // Shrink negative towards 0
              (problematic == min && value != min)) {
            // Always try min
            yield ShrinkableValue.leaf(problematic);
          }
        }
      }

      // Try regular shrinking towards zero (or min/max if zero is out of bounds)
      var current = value;
      final target = (min <= 0 && max >= 0) ? 0 : (value > 0 ? min : max);

      while (current != target) {
        final next = (current + target) ~/ 2; // Move halfway to target
        if (next == current) break; // Avoid infinite loop if no change
        // Ensure next is within bounds before yielding
        if (next >= min && next <= max) {
          yield ShrinkableValue.leaf(next);
        }
        current = next;
      }
      // Ensure the target itself is yielded if it wasn't reached and is valid
      if (current != target &&
          target >= min &&
          target <= max &&
          value != target) {
        yield ShrinkableValue.leaf(target);
      }
    });
  }
}

/// Internal implementation for generating chaotic JSON strings.
class _ChaoticJsonGenerator extends Generator<String> {
  final int maxDepth;
  final int maxLength;

  _ChaoticJsonGenerator({this.maxDepth = 3, this.maxLength = 10});

  @override
  ShrinkableValue<String> generate(Random random) {
    final value = generateJson(0, random); // Updated call

    return ShrinkableValue(value, () sync* {
      try {
        final decoded = json.decode(value);
        if (decoded is Map) {
          // Try removing keys
          final map = Map<String, dynamic>.from(decoded);
          for (final key in map.keys.toList()) {
            final tempMap = Map<String, dynamic>.from(map)..remove(key);
            yield ShrinkableValue.leaf(json.encode(tempMap));
          }
          // Try shrinking values within the map
          for (final entry in (decoded).entries) {
            // Simplified: only shrink leaf strings for now
            if (entry.value is String) {
              final stringVal = entry.value as String;
              if (stringVal.length > 1) {
                final tempMap = Map<String, dynamic>.from(map);
                tempMap[entry.key as String] = stringVal.substring(
                  0,
                  stringVal.length ~/ 2,
                );
                yield ShrinkableValue.leaf(json.encode(tempMap));
              }
            }
          }
        } else if (decoded is List) {
          // Try removing elements
          final list = decoded;
          if (list.isNotEmpty) {
            for (var i = 0; i < list.length; i++) {
              final tempList = [list]..removeAt(i);
              yield ShrinkableValue.leaf(json.encode(tempList));
            }
          }
          // Try shrinking elements within the list
          for (var i = 0; i < (decoded).length; i++) {
            final element = decoded[i];
            // Simplified: only shrink leaf strings for now
            if (element is String) {
              if (element.length > 1) {
                final tempList = [...list];
                tempList[i] = element.substring(0, element.length ~/ 2);
                yield ShrinkableValue.leaf(json.encode(tempList));
              }
            }
          }
        }
        // Try shrinking to simpler valid JSON types
        if (decoded is Map && (decoded).isNotEmpty) {
          yield ShrinkableValue.leaf('{}');
        }
        if (decoded is List && (decoded).isNotEmpty) {
          yield ShrinkableValue.leaf('[]');
        }
        if (value != 'null') yield ShrinkableValue.leaf('null');
        if (value != '""') yield ShrinkableValue.leaf('""');
        if (value != '0') yield ShrinkableValue.leaf('0');
        if (value != 'true') yield ShrinkableValue.leaf('true');
        if (value != 'false') yield ShrinkableValue.leaf('false');
      } catch (_) {
        // If we can't parse the JSON initially, try yielding simple valid JSON
        yield ShrinkableValue.leaf('{}');
        yield ShrinkableValue.leaf('[]');
        yield ShrinkableValue.leaf('null');
      }
    });
  }

  // Renamed local helper method
  String generateJson(int depth, Random random) {
    if (depth >= maxDepth) {
      return generateLeafValue(random);
    }

    switch (random.nextInt(3)) {
      case 0:
        return generateLeafValue(random);
      case 1:
        return generateObject(depth, random);
      default:
        return generateArray(depth, random);
    }
  }

  // Renamed local helper method
  String generateLeafValue(Random random) {
    switch (random.nextInt(4)) {
      case 0:
        return random.nextBool().toString();
      case 1:
        return random.nextInt(1000).toString();
      case 2:
        return 'null';
      default:
        return '"${generateString(random)}"';
    }
  }

  // Renamed local helper method
  String generateObject(int depth, Random random) {
    final length = random.nextInt(maxLength + 1); // Allow empty objects
    final entries = <String>[];

    for (var i = 0; i < length; i++) {
      final key = generateString(random);
      final value = generateJson(depth + 1, random);
      entries.add('"${_escapeString(key)}": $value'); // Escape key
    }

    return '{${entries.join(', ')}}';
  }

  // Renamed local helper method
  String generateArray(int depth, Random random) {
    final length = random.nextInt(maxLength + 1); // Allow empty arrays
    final elements = List.generate(
      length,
      (_) => generateJson(depth + 1, random),
    );

    return '[${elements.join(', ')}]';
  }

  // Renamed local helper method
  String generateString(Random random) {
    final length = random.nextInt(10);
    final chars = List.generate(
      length,
      (_) =>
          _ChaoticStringGenerator._problematicChars[random.nextInt(
            _ChaoticStringGenerator._problematicChars.length,
          )],
    );
    // Basic JSON string escaping
    return _escapeString(chars.join());
  }

  // Helper to escape strings for JSON
  String _escapeString(String s) {
    return s
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\b', r'\b')
        .replaceAll('\f', r'\f')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    // Note: Does not handle unicode escapes \uXXXX for simplicity here
  }
}

/// Internal implementation for generating chaotic byte lists.
class _ChaoticBytesGenerator extends Generator<List<int>> {
  final int minLength;
  final int maxLength;

  static const _problematicBytes = [
    0x00, // Null byte
    0xFF, // Max byte
    0x7F, // ASCII DEL
    0x1A, // EOF
    0x0A, // Line feed
    0x0D, // Carriage return
    0xFE, // UTF-16 BOM byte
    0xFF, // UTF-16 BOM byte / Max byte
    0xEF, // UTF-8 BOM byte
    0xBB, // UTF-8 BOM byte
    0xBF, // UTF-8 BOM byte
  ];

  _ChaoticBytesGenerator({int? minLength, int? maxLength})
    : minLength = minLength ?? 0,
      maxLength = maxLength ?? 100;

  @override
  ShrinkableValue<List<int>> generate(Random random) {
    final length = minLength + random.nextInt(maxLength - minLength + 1);
    final bytes = List<int>.generate(length, (i) {
      return random.nextBool()
          ? _problematicBytes[random.nextInt(_problematicBytes.length)]
          : random.nextInt(256);
    });

    return ShrinkableValue(bytes, () sync* {
      // Try removing bytes
      if (bytes.length > minLength) {
        // Shrink towards half the size first
        if (bytes.length > 1) {
          final halfLen = (bytes.length + minLength) ~/ 2;
          if (halfLen >= minLength && halfLen < bytes.length) {
            yield ShrinkableValue.leaf(bytes.sublist(0, halfLen));
          }
        }
        // Try removing individual bytes
        for (var i = 0; i < bytes.length; i++) {
          final shortened = List<int>.from(bytes)..removeAt(i);
          if (shortened.length >= minLength) {
            yield ShrinkableValue.leaf(shortened);
          }
        }
      }

      // Try replacing problematic bytes with zeros
      bool changed = false;
      final simplified = List<int>.from(bytes);
      for (var i = 0; i < bytes.length; i++) {
        if (_problematicBytes.contains(bytes[i]) && bytes[i] != 0) {
          simplified[i] = 0;
          changed = true;
        }
      }
      if (changed) {
        yield ShrinkableValue.leaf(simplified);
      }

      // Try yielding the minimal list if not already generated
      if (minLength > 0 && bytes.length > minLength) {
        final minList = List.filled(minLength, 0); // Simplest min-length list
        yield ShrinkableValue.leaf(minList);
      } else if (minLength == 0 && bytes.isNotEmpty) {
        yield ShrinkableValue.leaf([]); // Empty list
      }
    });
  }
}
