import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  group('Engine.builtins', () {
    test('returns all foundation providers', () {
      final providers = Engine.builtins;

      // routed_core owns only the foundation registrations. Feature providers
      // are registered by package:routed and its adapter dependencies.
      expect(providers.length, equals(3));

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
