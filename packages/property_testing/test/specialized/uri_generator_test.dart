import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('URI Generator Tests', () {
    test('handles special characters in query parameters', () async {
      final runner = PropertyTestRunner(
        Specialized.uri(includeQueryParameters: true),
        (uri) {
          for (final entry in uri.queryParameters.entries) {
            // Test that special characters are properly encoded
            final decoded = Uri.decodeQueryComponent(entry.value);
            final reEncoded = Uri.encodeQueryComponent(decoded);
            expect(Uri.parse(uri.toString()).queryParameters[entry.key],
                equals(decoded));
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('handles special characters in path segments', () async {
      final runner = PropertyTestRunner(
        Specialized.uri(),
        (uri) {
          for (final segment in uri.pathSegments) {
            // Test that special characters are properly encoded
            final decoded = Uri.decodeComponent(segment);
            final reEncoded = Uri.encodeComponent(decoded);
            expect(Uri.parse(uri.toString()).pathSegments, contains(decoded));
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid domain names', () async {
      final runner = PropertyTestRunner(
        Specialized.uri(),
        (uri) {
          print('Testing URI host: ${uri.host}');
          // Domain name should have at least a domain and TLD
          final parts = uri.host.split('.');
          print('Parts: $parts');
          expect(parts.length,
              greaterThanOrEqualTo(2)); // domain + TLD (subdomain optional)

          // Each part should be valid
          for (final part in parts.take(parts.length - 1)) {
            // All parts except TLD
            print('Checking part: $part');
            expect(
                part,
                matches(
                    r'^[a-z0-9-]+$')); // Only lowercase letters, numbers, and hyphens
            expect(
                part.length, lessThanOrEqualTo(63)); // Max length per DNS spec
          }

          // Check TLD
          print('Checking TLD: ${parts.last}');
          expect(
              parts.last, matches(r'^[a-z]+$')); // TLD should be letters only
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('maintains URI normalization properties', () async {
      final runner = PropertyTestRunner(
        Specialized.uri(
          includeUserInfo: true,
          includeQueryParameters: true,
          includeFragment: true,
        ),
        (uri) {
          print('Testing URI: $uri');
          final normalized = Uri.parse(uri.toString());
          print('Normalized: $normalized');

          // The toString representation should be preserved after parsing
          expect(normalized.toString(), equals(uri.toString()));

          // For file URIs without query parameters or fragments, toFilePath should work
          if (uri.scheme == 'file' &&
              uri.queryParameters.isEmpty &&
              uri.fragment == null) {
            try {
              final filePath = normalized.toFilePath(windows: false);
              // File path conversion worked
            } catch (e) {
              fail('Failed to convert valid file URI to path: $e');
            }
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('handles maximum URI length constraints', () async {
      final runner = PropertyTestRunner(
        Specialized.uri(
          maxPathSegments: 100,
          maxQueryParameters: 100,
        ),
        (uri) {
          // RFC 7230 suggests a minimum of 8000 octets for HTTP/1.1
          expect(uri.toString().length, lessThan(8000));
          // Check individual components are reasonable
          expect(uri.path.length, lessThan(2000));
          expect(uri.query.length, lessThan(2000));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });
  });
}
