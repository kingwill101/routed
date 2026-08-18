import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test(
    'batteries-included barrel registers the official feature providers',
    () {
      expect(officialProvidersRegistered, isTrue);
      final providers = Engine.builtins;
      expect(providers, hasLength(15));
      expect(
        ProviderRegistry.instance.registrations.map((entry) => entry.id),
        containsAll(<String>[
          'routed.core',
          'routed.routing',
          'routed.uploads',
          'routed.auth',
          'routed.logging',
          'routed.views',
          'routed.localization',
          'routed.observability',
          'routed.cache',
          'routed.sessions',
          'routed.storage',
          'routed.static',
          'routed.rate_limit',
          'routed.compression',
          'routed.security',
        ]),
      );
    },
  );
}
