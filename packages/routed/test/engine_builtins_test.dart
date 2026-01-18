import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('Engine.builtins', () {
    test('returns all built-in providers', () {
      final providers = Engine.builtins;

      // Should have all registered providers (currently 16)
      expect(providers.length, greaterThanOrEqualTo(16));

      // Verify core providers are included
      expect(
        providers.any((p) => p is CoreServiceProvider),
        isTrue,
        reason: 'Should include CoreServiceProvider',
      );
      expect(
        providers.any((p) => p is RoutingServiceProvider),
        isTrue,
        reason: 'Should include RoutingServiceProvider',
      );
    });

    test('returns more providers than defaultProviders', () {
      final builtins = Engine.builtins;
      final defaults = Engine.defaultProviders;

      expect(
        builtins.length,
        greaterThan(defaults.length),
        reason: 'builtins should include all providers, not just defaults',
      );
    });

    test('returns fresh instances each time', () {
      final first = Engine.builtins;
      final second = Engine.builtins;

      // Each call should return new provider instances
      expect(identical(first, second), isFalse);
      expect(identical(first[0], second[0]), isFalse);
    });
  });
}
