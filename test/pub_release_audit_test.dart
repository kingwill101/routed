import 'package:test/test.dart';

import '../tool/pub_release_audit.dart';

void main() {
  group('compareVersions', () {
    test('compares release versions numerically', () {
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('0.3.3', '0.3.3'), 0);
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
    });

    test('follows prerelease precedence', () {
      expect(compareVersions('1.0.0-alpha', '1.0.0'), lessThan(0));
      expect(compareVersions('1.0.0-alpha.2', '1.0.0-alpha.10'), lessThan(0));
      expect(compareVersions('1.0.0-beta', '1.0.0-alpha'), greaterThan(0));
    });

    test('ignores build metadata for precedence', () {
      expect(compareVersions('0.1.0+2', '0.1.0+1'), 0);
    });
  });
}
