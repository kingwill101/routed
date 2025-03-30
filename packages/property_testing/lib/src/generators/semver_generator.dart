import 'dart:math' as math;

import '../generator_base.dart';

/// Generator for semantic version strings
/// A generator that produces semantic version strings (SemVer).
///
/// Can optionally include `prerelease` identifiers (e.g., `-alpha.1`) and
/// `build` metadata (e.g., `+build.123`). Generates version numbers with
/// a distribution favoring lower numbers.
///
/// Shrinking attempts to remove build metadata, then prerelease identifiers,
/// reduce version numbers towards `0.1.0` or `1.0.0`.
///
/// Usually used via [Specialized.semver].
///
/// ```dart
/// final semverGen = Specialized.semver(prerelease: false, build: true);
/// final runner = PropertyTestRunner(semverGen, (version) {
///   // Test property with generated version string
/// });
/// await runner.run();
/// ```
class SemverGenerator extends Generator<String> {
  final bool prerelease;
  final bool build;

  SemverGenerator({
    this.prerelease = true,
    this.build = true,
  });

  @override
  ShrinkableValue<String> generate(math.Random random) {
    // Use the provided random generator
    final major = random.nextInt(10); // 0-9
    final minor = random.nextInt(20); // 0-19
    final patch = random.nextInt(50); // 0-49

    var version = '$major.$minor.$patch';

    // Add prerelease with 50% probability if enabled
    if (prerelease && random.nextBool()) {
      version += '-${_generatePrerelease(random)}';
    }

    // Add build metadata with 50% probability if enabled
    if (build && random.nextBool()) {
      version += '+${_generateBuild(random)}';
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
