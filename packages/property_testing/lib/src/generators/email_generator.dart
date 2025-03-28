import 'dart:math' as math;

import '../generator_base.dart';

/// Generator for email addresses
class EmailGenerator extends Generator<String> {
  final List<String> domains;
  final int maxLocalPartLength;

  static const _defaultDomains = [
    'gmail.com',
    'yahoo.com',
    'hotmail.com',
    'outlook.com',
    'example.com',
  ];

  EmailGenerator({
    List<String>? domains,
    this.maxLocalPartLength = 64,
  }) : domains = domains ?? _defaultDomains {
    if (maxLocalPartLength < 1 || maxLocalPartLength > 64) {
      throw ArgumentError.value(
        maxLocalPartLength,
        'maxLocalPartLength',
        'Must be between 1 and 64',
      );
    }
  }

  @override
  ShrinkableValue<String> generate([math.Random? random]) {
    // Always use the provided random generator, don't create a new one
    if (random == null) {
      throw ArgumentError('Random generator must be provided');
    }
    final localPart = _generateLocalPart(random);
    final domain = domains[random.nextInt(domains.length)];
    final value = '$localPart@$domain';

    return ShrinkableValue(value, () sync* {
      // Try shrinking local part
      if (localPart.length > 1) {
        final simplified = localPart.substring(0, localPart.length ~/ 2);
        if (_isValidLocalPart(simplified)) {
          yield ShrinkableValue.leaf('$simplified@$domain');
        }
      }

      // Try common local parts
      final commonLocalParts = ['test', 'user', 'admin'];
      for (final part in commonLocalParts) {
        if (part.length < localPart.length) {
          yield ShrinkableValue.leaf('$part@$domain');
        }
      }
    });
  }

  String _generateLocalPart(math.Random random) {
    if (maxLocalPartLength == 1) {
      final chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      return chars[random.nextInt(chars.length)];
    }

    final length = 1 + random.nextInt(maxLocalPartLength - 1);
    final chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final specialChars = '._-';
    final buffer = StringBuffer();

    // First character must be alphanumeric
    buffer.write(chars[random.nextInt(chars.length)]);

    // Generate remaining characters
    for (var i = 1; i < length - 1; i++) {
      if (random.nextInt(5) == 0 && // 20% chance for special char
          !specialChars.contains(buffer.toString()[i - 1])) {
        // No consecutive specials
        buffer.write(specialChars[random.nextInt(specialChars.length)]);
      } else {
        buffer.write(chars[random.nextInt(chars.length)]);
      }
    }

    // Last character must be alphanumeric
    if (length > 1) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }

    return buffer.toString();
  }

  bool _isValidLocalPart(String part) {
    if (part.isEmpty || part.length > 64) return false;
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*[a-zA-Z0-9]$').hasMatch(part))
      return false;
    if (part.contains('..') || part.contains('__') || part.contains('--'))
      return false;
    return true;
  }
}
