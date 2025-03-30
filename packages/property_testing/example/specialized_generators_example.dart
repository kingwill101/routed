import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Specialized Generator Examples', () {
    test('DateTime properties', () async {
      final runner = PropertyTestRunner(
        Specialized.dateTime(
          min: DateTime(2000),
          max: DateTime(2024),
          utc: true,
        ),
        (date) {
          // Test that dates are within range and in UTC
          expect(date.isUtc, isTrue);
          expect(date.year, greaterThanOrEqualTo(2000));
          expect(date.year, lessThanOrEqualTo(2024));
        },
      );

      final result = await runner.run();
    });

    test('Duration arithmetic properties', () async {
      final runner = PropertyTestRunner(
        Specialized.duration(
          min: Duration.zero,
          max: const Duration(days: 30),
        ),
        (duration) {
          // Test duration arithmetic properties
          expect(duration + Duration.zero, equals(duration));
          expect(duration * 1, equals(duration));
          expect(duration.isNegative, isFalse);
        },
      );

      final result = await runner.run();
    });

    test('URI parsing properties', () async {
      final runner = PropertyTestRunner(
        Specialized.uri(
          schemes: ['https'],
          includeUserInfo: true,
          maxPathSegments: 3,
          maxQueryParameters: 2,
        ),
        (uri) {
          // Test that URIs can be parsed and reconstructed
          final parsed = Uri.parse(uri.toString());
          expect(parsed.scheme, equals(uri.scheme));
          expect(parsed.host, equals(uri.host));
          expect(parsed.pathSegments, equals(uri.pathSegments));
          expect(parsed.queryParameters, equals(uri.queryParameters));
        },
      );

      final result = await runner.run();
    });

    test('Email validation properties', () async {
      final runner = PropertyTestRunner(
        Specialized.email(
          domains: ['example.com', 'test.org'],
          maxLocalPartLength: 32,
        ),
        (email) {
          // Test email format
          expect(email, contains('@'));
          final parts = email.split('@');
          expect(parts.length, equals(2));
          expect(parts[0].length, greaterThan(0));
          expect(parts[0].length, lessThanOrEqualTo(32));
          expect(['example.com', 'test.org'], contains(parts[1]));
        },
      );

      final result = await runner.run();
    });

    test('Semantic version ordering properties', () async {
      final runner = PropertyTestRunner(
        Specialized.semver(prerelease: true, build: true)
            .list(minLength: 2, maxLength: 2),
        (versions) {
          // Parse and compare version strings
          final v1 = _SemVer.parse(versions[0]);
          final v2 = _SemVer.parse(versions[1]);

          // Test transitivity of comparisons
          if (v1.compareTo(v2) > 0) {
            expect(v2.compareTo(v1), lessThan(0));
          } else if (v1.compareTo(v2) < 0) {
            expect(v2.compareTo(v1), greaterThan(0));
          } else {
            expect(v2.compareTo(v1), equals(0));
          }
        },
      );

      final result = await runner.run();
    });

    test('Color blending properties', () async {
      final runner = PropertyTestRunner(
        Specialized.color(alpha: true).list(minLength: 2, maxLength: 2),
        (colors) {
          final c1 = colors[0];
          final c2 = colors[1];

          // Test color blending properties
          final blended = _blendColors(c1, c2, 0.5);

          // Alpha should be between the two colors
          expect(blended.a, greaterThanOrEqualTo(min(c1.a, c2.a)));
          expect(blended.a, lessThanOrEqualTo(max(c1.a, c2.a)));

          // RGB components should be between the two colors
          expect(blended.r, greaterThanOrEqualTo(min(c1.r, c2.r)));
          expect(blended.r, lessThanOrEqualTo(max(c1.r, c2.r)));
          expect(blended.g, greaterThanOrEqualTo(min(c1.g, c2.g)));
          expect(blended.g, lessThanOrEqualTo(max(c1.g, c2.g)));
          expect(blended.b, greaterThanOrEqualTo(min(c1.b, c2.b)));
          expect(blended.b, lessThanOrEqualTo(max(c1.b, c2.b)));
        },
        );
  
      final result = await runner.run();
    });
      });
}

/// Simple semantic version class for comparison testing
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

/// Helper function to blend two colors
Color _blendColors(Color c1, Color c2, double t) {
  return Color(
    r: (c1.r + (c2.r - c1.r) * t).round(),
    g: (c1.g + (c2.g - c1.g) * t).round(),
    b: (c1.b + (c2.b - c1.b) * t).round(),
    a: c1.a + (c2.a - c1.a) * t,
  );
}

/// Helper function to find the minimum of two numbers
T min<T extends num>(T a, T b) => a < b ? a : b;

/// Helper function to find the maximum of two numbers
T max<T extends num>(T a, T b) => a > b ? a : b;
