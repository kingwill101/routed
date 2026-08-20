import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:server_auth/testing.dart';

Engine _engine() {
  final engine = Engine(providers: Engine.defaultProviders);
  engine.post('/conformance', (context) async {
    final environment = cloudflareEnvironmentOf(context);
    if (environment == null) {
      return context.json({
        'error': 'cloudflare_environment_unavailable',
      }, statusCode: 500);
    }
    final database = environment.d1('AUTH_DB');
    var fixture = 0;
    final suite = AuthStoreConformanceSuite(
      createFixture: () async {
        final schema = CloudflareD1AuthSchema(
          tablePrefix:
              'live_auth_${DateTime.now().microsecondsSinceEpoch}_${fixture++}',
        );
        final store = await CloudflareD1AuthStore.open(
          database,
          schema: schema,
        );
        return AuthStoreConformanceFixture(
          store: store,
          dispose: () => schema.dropAll(database),
        );
      },
    );

    final results = <Map<String, Object?>>[];
    for (final conformanceCase in suite.cases) {
      try {
        final result = await conformanceCase.run();
        final expectedSkip =
            conformanceCase.optionalCapability ==
            AuthStoreConformanceCapability.accountDeletion;
        results.add({
          'id': conformanceCase.id,
          'passed': expectedSkip ? result.isSkipped : !result.isSkipped,
          'skipped': result.skippedReason,
        });
      } catch (error) {
        results.add({
          'id': conformanceCase.id,
          'passed': false,
          'error': error.toString(),
        });
      }
    }
    return context.json({
      'passed': results.every((result) => result['passed'] == true),
      'results': results,
    });
  });
  return engine;
}

void main() {
  defineCloudflareFetchFactoryAsync(() async => _engine());
}
