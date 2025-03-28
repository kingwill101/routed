import 'dart:math' as math;

import '../generator_base.dart';

/// Generator for semantic version strings
class SemverGenerator extends Generator<String> {
  final bool prerelease;
  final bool build;

  SemverGenerator({
    this.prerelease = true,
    this.build = true,
  });

  @override
  ShrinkableValue<String> generate([math.Random? random]) {
    final rng = random ?? math.Random(42);

    // Generate version numbers with good distribution
    final major = rng.nextInt(10); // 0-9
    final minor = rng.nextInt(20); // 0-19
    final patch = rng.nextInt(50); // 0-49

    var version = '$major.$minor.$patch';

    // Add prerelease with 50% probability if enabled
    if (prerelease && rng.nextBool()) {
      version += '-${_generatePrerelease(rng)}';
    }

    // Add build metadata with 50% probability if enabled
    if (build && rng.nextBool()) {
      version += '+${_generateBuild(rng)}';
    }

    return ShrinkableValue(version, () sync* {
      // Try removing build metadata
      if (version.contains('+')) {
        yield ShrinkableValue.leaf(
          version.substring(0, version.indexOf('+')),
        );
      }

      // Try removing prerelease
      if (version.contains('-')) {
        yield ShrinkableValue.leaf(
          version.substring(0, version.indexOf('-')),
        );
      }

      // Try reducing version numbers
      final parts = version.split('.');
      final base = parts[0];
      if (base != '0') {
        yield ShrinkableValue.leaf(
            '0.${parts[1]}.${parts[2].replaceFirst(RegExp(r'[-+].*$'), '')}');
      }

      // Try common version patterns
      final commonVersions = [
        '0.1.0',
        '1.0.0',
        '2.0.0',
      ];

      for (final ver in commonVersions) {
        if (ver.compareTo(version) < 0) {
          yield ShrinkableValue.leaf(ver);
        }
      }
    });
  }

  String _generatePrerelease(math.Random random) {
    final identifiers = <String>[];
    final count = random.nextInt(2) + 1;

    for (var i = 0; i < count; i++) {
      if (random.nextBool()) {
        // Numeric identifier (must not have leading zeros)
        final num = random.nextInt(99) + 1;
        identifiers.add(num.toString());
      } else {
        // Alphanumeric identifier with good distribution
        final length = random.nextInt(8) + 1;
        final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
        final buffer = StringBuffer();

        // First character must be a letter
        buffer.write(chars[random.nextInt(26)]);

        // Rest can be alphanumeric with mixed case
        for (var j = 1; j < length; j++) {
          final char = chars[random.nextInt(chars.length)];
          buffer.write(random.nextBool() ? char.toUpperCase() : char);
        }
        identifiers.add(buffer.toString());
      }
    }

    return identifiers.join('.');
  }

  String _generateBuild(math.Random random) {
    final identifiers = <String>[];
    final count = random.nextInt(2) + 1;

    for (var i = 0; i < count; i++) {
      final length = random.nextInt(8) + 1;
      final chars =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      final buffer = StringBuffer();

      // First character must be alphanumeric
      buffer.write(chars[random.nextInt(chars.length)]);

      // Rest can be alphanumeric with mixed case
      for (var j = 1; j < length; j++) {
        final char = chars[random.nextInt(chars.length)];
        buffer.write(random.nextBool() ? char.toUpperCase() : char);
      }
      identifiers.add(buffer.toString());
    }

    return identifiers.join('.');
  }
}
