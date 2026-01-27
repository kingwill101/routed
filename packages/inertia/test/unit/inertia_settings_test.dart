/// Tests for [InertiaSettings] behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia_dart.dart';

/// Runs Inertia settings unit tests.
void main() {
  test('InertiaSettings copyWith overrides values', () {
    final settings = InertiaSettings(
      version: '1.0',
      ssrEnabled: false,
      ssrEndpoint: Uri.parse('http://localhost:13714'),
    );

    final updated = settings.copyWith(version: '2.0', ssrEnabled: true);

    expect(updated.version, equals('2.0'));
    expect(updated.ssrEnabled, isTrue);
    expect(updated.ssrEndpoint.toString(), equals('http://localhost:13714'));
  });
}
