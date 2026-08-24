import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  test(
    'Routed deployment helpers reject non-EngineContext deployments',
    () async {
      final packageRoot = _findPackageRoot();
      final fixture = File(
        '${packageRoot.path}/test/fixtures/'
        'auth_deployment_invalid_context.dart.txt',
      );
      final source = File(
        '${packageRoot.path}/.dart_tool/'
        'auth_deployment_invalid_context_$pid.dart',
      );
      await source.writeAsString(await fixture.readAsString());
      addTearDown(() async {
        if (source.existsSync()) source.deleteSync();
      });

      final result = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        source.path,
      ], workingDirectory: packageRoot.path);
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, isNot(0), reason: output);
      expect(output, contains("The method 'bindTo' isn't defined"));
      expect(output, contains("The method 'serviceProvider' isn't defined"));
      expect(output, contains("The method 'engineConfig' isn't defined"));
    },
  );

  test('Routed deployment installs AuthManager and routes', () async {
    final deployment = AuthDeploymentPresets.localDevelopment<EngineContext>(
      providers: [CredentialsProvider()],
      trustedOrigins: [Uri.parse('http://localhost:3000')],
    );

    final provider = deployment.serviceProvider();
    final engine = Engine(
      config: deployment.engineConfig(),
      providers: [...Engine.defaultProviders, provider],
    );
    deployment.bindTo(engine);
    addTearDown(engine.close);

    await engine.initialize();

    expect(
      engine.container.get<AuthOptions<EngineContext>>(),
      same(deployment.options),
    );
    final manager = engine.container.get<AuthManager>();
    expect(manager.options.store, same(deployment.options.store));
    expect(manager.options.basePath, deployment.options.basePath);
    expect(provider.configuration, same(deployment.configuration));
    expect(deployment.options.runtimeMode, AuthRuntimeMode.localDevelopment);
    expect(engine.config.features.enableProxySupport, isFalse);

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);
    final response = await client.get('/auth/providers');
    response.assertStatus(HttpStatus.ok);
    expect(
      response.json()['providers'],
      contains(containsPair('id', 'credentials')),
    );
  });

  test('deployment provider rejects a missing EngineContext binding', () async {
    final deployment = AuthDeploymentPresets.localDevelopment<EngineContext>(
      providers: [CredentialsProvider()],
      trustedOrigins: [Uri.parse('http://localhost:3000')],
    );
    final engine = Engine(
      config: deployment.engineConfig(),
      providers: [...Engine.defaultProviders, deployment.serviceProvider()],
    );
    addTearDown(engine.close);

    // This binding previously let startup succeed while Routed silently
    // ignored the deployment because its context did not match EngineContext.
    engine.container.instance<AuthOptions<String>>(
      AuthOptions<String>(
        providers: [CredentialsProvider()],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
      ),
    );

    await expectLater(
      engine.initialize(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('deployment was not bound'),
        ),
      ),
    );
    expect(engine.container.has<AuthManager>(), isFalse);
  });

  test(
    'deployment provider rejects substituted EngineContext options',
    () async {
      final deployment = AuthDeploymentPresets.localDevelopment<EngineContext>(
        providers: [CredentialsProvider()],
        trustedOrigins: [Uri.parse('http://localhost:3000')],
      );
      final engine = Engine(
        config: deployment.engineConfig(),
        providers: [...Engine.defaultProviders, deployment.serviceProvider()],
      );
      addTearDown(engine.close);
      engine.container.instance<AuthOptions<EngineContext>>(
        AuthOptions<EngineContext>(
          providers: [CredentialsProvider()],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
        ),
      );

      await expectLater(
        engine.initialize(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('do not match'),
          ),
        ),
      );
      expect(engine.container.has<AuthManager>(), isFalse);
    },
  );

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

  test('production provider rejects an unapplied proxy boundary', () async {
    final deployment =
        AuthDeploymentPresets.secureSessionProduction<EngineContext>(
          store: _OpaqueDurableStore(),
          providers: const <AuthProvider>[],
          boundary: AuthProductionBoundary(
            trustedOrigins: [Uri.parse('https://app.example.com')],
            proxyPolicy: AuthProxyPolicy.trusted(
              proxies: ['10.0.0.0/8'],
              headers: ['CF-Connecting-IP'],
            ),
          ),
          lifecycleDelivery:
              const AuthLifecycleDelivery<EngineContext>.disabled(),
          rateLimiter: _AllowAllRateLimiter(),
          requireVerifiedEmail: true,
        );
    final engine = Engine(
      providers: [...Engine.defaultProviders, deployment.serviceProvider()],
    );
    addTearDown(engine.close);
    deployment.bindTo(engine);

    await expectLater(
      engine.initialize(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('deployment.engineConfig()'),
        ),
      ),
    );
    expect(engine.container.has<AuthManager>(), isFalse);
  });
}

Directory _findPackageRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final direct = File('${current.path}/pubspec.yaml');
    if (direct.existsSync() &&
        direct.readAsStringSync().contains('name: routed_auth')) {
      return current;
    }
    final workspacePackage = Directory('${current.path}/packages/routed_auth');
    final workspacePubspec = File('${workspacePackage.path}/pubspec.yaml');
    if (workspacePubspec.existsSync()) return workspacePackage;
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the routed_auth package root.');
    }
    current = parent;
  }
}

final class _OpaqueDurableStore implements AuthStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AllowAllRateLimiter implements AuthRateLimiter<EngineContext> {
  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) =>
      const AuthRateLimitDecision.allow();
}
