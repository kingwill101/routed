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

    final provider = deployment.serviceProvider();
    final engine = Engine(
      config: deployment.engineConfig(),
      providers: [...Engine.defaultProviders, provider],
    );
    deployment.bindTo(engine);

    expect(
      engine.container.get<AuthOptions<EngineContext>>(),
      same(deployment.options),
    );
    expect(provider.configuration, same(deployment.configuration));
    expect(provider.requireDurableStore, isFalse);
    expect(engine.config.features.enableProxySupport, isFalse);
  });

  test('Routed binding applies only explicitly trusted proxies', () {
    final deployment = AuthDeployment<EngineContext>.custom(
      options: AuthOptions<EngineContext>(
        providers: [CredentialsProvider()],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      ),
      configuration: AuthConfig.defaults(),
      proxyPolicy: AuthProxyPolicy.trusted(
        proxies: ['10.0.0.0/8'],
        headers: ['CF-Connecting-IP'],
        platformHeader: 'CF-Connecting-IP',
      ),
    );

    final config = deployment.engineConfig(
      EngineConfig(
        features: const EngineFeatures(enableTrieRouting: true),
        redirectTrailingSlash: false,
      ),
    );

    expect(config.features.enableProxySupport, isTrue);
    expect(config.features.enableTrustedPlatform, isTrue);
    expect(config.features.enableTrieRouting, isTrue);
    expect(config.forwardedByClientIP, isTrue);
    expect(config.trustedProxies, ['10.0.0.0/8']);
    expect(config.remoteIPHeaders, ['CF-Connecting-IP']);
    expect(config.trustedPlatform, 'CF-Connecting-IP');
    expect(config.redirectTrailingSlash, isFalse);
  });
}
