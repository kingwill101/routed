import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';
import 'dart:math';

void main() {
  group('SemVer Generator', () {
    test('generates valid semantic versions with default settings', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(),
        (version) {
          expect(version, matches(r'^\d+\.\d+\.\d+(?:-[\w.]+)?(?:\+[\w.]+)?$'));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates versions without prerelease when disabled', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(prerelease: false),
        (version) {
          expect(version, isNot(contains('-')));
          expect(version, matches(r'^\d+\.\d+\.\d+(?:\+[\w.]+)?$'));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates versions without build metadata when disabled', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(build: false),
        (version) {
          expect(version, isNot(contains('+')));
          expect(version, matches(r'^\d+\.\d+\.\d+(?:-[\w.]+)?$'));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid prerelease identifiers', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(prerelease: true, build: false),
        (version) {
          if (version.contains('-')) {
            final prerelease = version.split('-')[1];
            final identifiers = prerelease.split('.');

            for (final id in identifiers) {
              // Each identifier must be either numeric or alphanumeric
              expect(id, matches(r'^\d+$|^[0-9A-Za-z-]+$'));
              // Numeric identifiers must not have leading zeros
              if (id.contains(RegExp(r'^\d+$'))) {
                expect(id, isNot(startsWith('0')));
              }
            }
          }
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid build metadata identifiers', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(prerelease: false, build: true),
        (version) {
          if (version.contains('+')) {
            final build = version.split('+')[1];
            final identifiers = build.split('.');

            for (final id in identifiers) {
              // Build identifiers can contain alphanumerics and hyphens
              expect(id, matches(r'^[0-9A-Za-z-]+$'));
            }
          }
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('shrinks while maintaining valid semver format', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(prerelease: true, build: true),
        (version) {
          // Force failure to trigger shrinking
          fail('Triggering shrink');
        },
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);

      final shrunkVersion = result.failingInput as String;
      expect(
          shrunkVersion, matches(r'^\d+\.\d+\.\d+(?:-[\w.]+)?(?:\+[\w.]+)?$'));
    });

    test('generates reproducible versions from the same seed', () async {
      final random = Random(42); // Create a fixed random seed
      final config = PropertyConfig(numTests: 10, random: random);
      final generator = Specialized.semver(prerelease: true, build: true);

      final versions1 = <String>[];
      await PropertyTestRunner(
        generator,
        (version) => versions1.add(version),
        config,
      ).run();

      // Reset the random generator to the same seed
      final random2 = Random(42);
      final config2 = PropertyConfig(numTests: 10, random: random2);

      final versions2 = <String>[];
      await PropertyTestRunner(
        generator,
        (version) => versions2.add(version),
        config2,
      ).run();

      expect(versions1, equals(versions2));
    });

    test('generates versions that follow semver ordering rules', () async {
      final runner = PropertyTestRunner(
        Specialized.semver().list(minLength: 2, maxLength: 2),
        (versions) {
          final v1 = _SemVer.parse(versions[0]);
          final v2 = _SemVer.parse(versions[1]);

          // Test that comparison is consistent
          if (v1.compareTo(v2) > 0) {
            expect(v2.compareTo(v1), lessThan(0));
          } else if (v1.compareTo(v2) < 0) {
            expect(v2.compareTo(v1), greaterThan(0));
          } else {
            expect(v2.compareTo(v1), equals(0));
          }
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates diverse version components', () async {
      final seenMajor = <int>{};
      final seenMinor = <int>{};
      final seenPatch = <int>{};
      final seenPrerelease = <String>{};
      final seenBuild = <String>{};

      final runner = PropertyTestRunner(
        Specialized.semver(prerelease: true, build: true),
        (version) {
          final semver = _SemVer.parse(version);
          seenMajor.add(semver.major);
          seenMinor.add(semver.minor);
          seenPatch.add(semver.patch);
          if (semver.prerelease != null) seenPrerelease.add(semver.prerelease!);
          if (semver.build != null) seenBuild.add(semver.build!);
        },
        PropertyConfig(numTests: 1000),
      );

      await runner.run();

      // We should see a good distribution of values
      expect(seenMajor.length, greaterThan(3));
      expect(seenMinor.length, greaterThan(5));
      expect(seenPatch.length, greaterThan(10));
      expect(seenPrerelease.length, greaterThan(10));
      expect(seenBuild.length, greaterThan(10));
    });
  });
}

/// Helper class for parsing and comparing semantic versions
class _SemVer implements Comparable<_SemVer> {
  final int major;
  final int minor;
  final int patch;
  final String? prerelease;
  final String? build;

  _SemVer(this.major, this.minor, this.patch, [this.prerelease, this.build]);

  static _SemVer parse(String version) {
    final parts = version.split('+');
    final buildMetadata = parts.length > 1 ? parts[1] : null;

    final versionParts = parts[0].split('-');
    final prerelease = versionParts.length > 1 ? versionParts[1] : null;

    final numbers = versionParts[0].split('.').map(int.parse).toList();
    return _SemVer(
      numbers[0],
      numbers[1],
      numbers[2],
      prerelease,
      buildMetadata,
    );
  }

  @override
  int compareTo(_SemVer other) {
    // Compare major.minor.patch
    var result = major.compareTo(other.major);
    if (result != 0) return result;

    result = minor.compareTo(other.minor);
    if (result != 0) return result;

    result = patch.compareTo(other.patch);
    if (result != 0) return result;

    // Pre-release versions are lower than the normal version
    if (prerelease == null && other.prerelease != null) return 1;
    if (prerelease != null && other.prerelease == null) return -1;
    if (prerelease != null && other.prerelease != null) {
      return prerelease!.compareTo(other.prerelease!);
    }

    return 0;
  }
}
