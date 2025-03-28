import 'dart:convert';
import 'dart:math' show Random;

import 'generator_base.dart';

/// Categories of chaotic data
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
class ChaosConfig {
  /// The categories of chaos to include
  final Set<ChaosCategory> categories;

  /// The maximum length for generated strings
  final int maxLength;

  /// The probability of including each type of chaos (0.0 to 1.0)
  final double intensity;

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

/// A collection of chaos generators for testing edge cases and security issues
class Chaos {
  static final _random = Random(42);

  /// Generate chaotic strings
  static Generator<String> string({
    int? minLength,
    int? maxLength,
  }) =>
      _ChaoticStringGenerator(minLength: minLength, maxLength: maxLength);

  /// Generate chaotic integers
  static Generator<int> integer({
    int? min,
    int? max,
  }) =>
      _ChaoticIntGenerator(min: min, max: max);

  /// Generate chaotic JSON
  static Generator<String> json({
    int maxDepth = 3,
    int maxLength = 10,
  }) =>
      _ChaoticJsonGenerator(maxDepth: maxDepth, maxLength: maxLength);

  /// Generate chaotic byte arrays
  static Generator<List<int>> bytes({
    int? minLength,
    int? maxLength,
  }) =>
      _ChaoticBytesGenerator(minLength: minLength, maxLength: maxLength);
}

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

  _ChaoticStringGenerator({
    int? minLength,
    int? maxLength,
  })  : minLength = minLength ?? 0,
        maxLength = maxLength ?? 100;

  @override
  ShrinkableValue<String> generate([Random? random]) {
    final rng = random ?? Random(42);
    final length = minLength + rng.nextInt(maxLength - minLength + 1);
    final buffer = StringBuffer();

    for (var i = 0; i < length; i++) {
      if (rng.nextBool()) {
        // Use a problematic character
        buffer.write(_problematicChars[rng.nextInt(_problematicChars.length)]);
      } else {
        // Use a random Unicode character
        buffer.writeCharCode(rng.nextInt(0x10FFFF));
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
            value.substring(0, i) + ' ' + value.substring(i + 1),
          );
        }
      }
    });
  }
}

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

  _ChaoticIntGenerator({
    int? min,
    int? max,
  })  : min = min ?? -9223372036854775808,
        max = max ?? 9223372036854775807;

  @override
  ShrinkableValue<int> generate([Random? random]) {
    final rng = random ?? Random(42);
    final useProblematic = rng.nextBool();

    final value = useProblematic
        ? _edgeCases[rng.nextInt(_edgeCases.length)]
        : min + rng.nextInt(max - min + 1);

    return ShrinkableValue(value, () sync* {
      // Try problematic values that are smaller
      for (final problematic in _edgeCases) {
        if (problematic < value && problematic >= min) {
          yield ShrinkableValue.leaf(problematic);
        }
      }

      // Try regular shrinking
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

class _ChaoticJsonGenerator extends Generator<String> {
  final int maxDepth;
  final int maxLength;

  _ChaoticJsonGenerator({
    this.maxDepth = 3,
    this.maxLength = 10,
  });

  @override
  ShrinkableValue<String> generate([Random? random]) {
    final rng = random ?? Random(42);
    final value = _generateJson(0, rng);

    return ShrinkableValue(value, () sync* {
      try {
        final decoded = json.decode(value);
        if (decoded is Map) {
          // Try removing keys
          final map = Map<String, dynamic>.from(decoded);
          for (final key in map.keys.toList()) {
            map.remove(key);
            yield ShrinkableValue.leaf(json.encode(map));
          }
        } else if (decoded is List) {
          // Try removing elements
          final list = List.from(decoded);
          for (var i = 0; i < list.length; i++) {
            list.removeAt(i);
            yield ShrinkableValue.leaf(json.encode(list));
          }
        }
      } catch (_) {
        // If we can't parse the JSON, we can't shrink it
      }
    });
  }

  String _generateJson(int depth, Random random) {
    if (depth >= maxDepth) {
      return _generateLeafValue(random);
    }

    switch (random.nextInt(3)) {
      case 0:
        return _generateLeafValue(random);
      case 1:
        return _generateObject(depth, random);
      default:
        return _generateArray(depth, random);
    }
  }

  String _generateLeafValue(Random random) {
    switch (random.nextInt(4)) {
      case 0:
        return random.nextBool().toString();
      case 1:
        return random.nextInt(1000).toString();
      case 2:
        return 'null';
      default:
        return '"${_generateString(random)}"';
    }
  }

  String _generateObject(int depth, Random random) {
    final length = random.nextInt(maxLength);
    final entries = <String>[];

    for (var i = 0; i < length; i++) {
      final key = _generateString(random);
      final value = _generateJson(depth + 1, random);
      entries.add('"$key": $value');
    }

    return '{${entries.join(', ')}}';
  }

  String _generateArray(int depth, Random random) {
    final length = random.nextInt(maxLength);
    final elements = List.generate(
      length,
      (_) => _generateJson(depth + 1, random),
    );

    return '[${elements.join(', ')}]';
  }

  String _generateString(Random random) {
    final length = random.nextInt(10);
    final chars = List.generate(
      length,
      (_) => _ChaoticStringGenerator._problematicChars[
          random.nextInt(_ChaoticStringGenerator._problematicChars.length)],
    );
    return chars.join();
  }
}

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
    0xFE, // UTF-16 BOM
    0xEF, // UTF-8 BOM
    0xBB, // UTF-8 BOM
    0xBF, // UTF-8 BOM
  ];

  _ChaoticBytesGenerator({
    int? minLength,
    int? maxLength,
  })  : minLength = minLength ?? 0,
        maxLength = maxLength ?? 100;

  @override
  ShrinkableValue<List<int>> generate([Random? random]) {
    final rng = random ?? Random(42);
    final length = minLength + rng.nextInt(maxLength - minLength + 1);
    final bytes = List<int>.generate(length, (i) {
      return rng.nextBool()
          ? _problematicBytes[rng.nextInt(_problematicBytes.length)]
          : rng.nextInt(256);
    });

    return ShrinkableValue(bytes, () sync* {
      // Try removing bytes
      if (bytes.length > minLength) {
        for (var i = 0; i < bytes.length; i++) {
          final shortened = List<int>.from(bytes)..removeAt(i);
          if (shortened.length >= minLength) {
            yield ShrinkableValue.leaf(shortened);
          }
        }
      }

      // Try replacing problematic bytes with zeros
      for (var i = 0; i < bytes.length; i++) {
        if (_problematicBytes.contains(bytes[i])) {
          final simplified = List<int>.from(bytes);
          simplified[i] = 0;
          yield ShrinkableValue.leaf(simplified);
        }
      }
    });
  }
}
