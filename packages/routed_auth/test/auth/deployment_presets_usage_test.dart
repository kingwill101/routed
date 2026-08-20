import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  test('Routed app can bind a typed auth deployment without maps', () {
    final AuthDeployment<EngineContext> deployment =
        AuthDeploymentPresets.localDevelopment<EngineContext>(
          providers: [CredentialsProvider()],
          trustedOrigins: [Uri.parse('http://localhost:3000')],
        );

    final provider = AuthServiceProvider(
      configuration: deployment.configuration,
      requireDurableStore: deployment.requiresDurableStore,
    );
    final engine = Engine(providers: [...Engine.defaultProviders, provider]);
    engine.container.instance<AuthOptions<EngineContext>>(deployment.options);

    expect(
      engine.container.get<AuthOptions<EngineContext>>(),
      same(deployment.options),
    );
    expect(provider.configuration, same(deployment.configuration));
    expect(provider.requireDurableStore, isFalse);
  });
}
