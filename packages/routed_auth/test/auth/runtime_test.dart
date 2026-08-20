import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

void main() {
  test('AuthManager exposes the composed runtime store', () {
    final options = AuthOptions<EngineContext>(
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      providers: const <AuthProvider>[],
    );
    final runtime = AuthRuntime<EngineContext>(options: options);
    final manager = AuthManager(options, runtime: runtime);

    expect(manager.runtime, same(runtime));
    expect(manager.store, same(runtime.store));
  });

  test('AuthServiceProvider accepts an explicit local posture', () async {
    final options = AuthOptions<EngineContext>(
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      providers: const <AuthProvider>[],
    );
    final engine = testEngine(providers: [AuthServiceProvider()]);
    addTearDown(engine.close);
    engine.container.instance<AuthOptions<EngineContext>>(options);

    await engine.initialize();

    expect(options.runtimeMode, AuthRuntimeMode.localDevelopment);
    expect(engine.container.has<AuthManager>(), isTrue);
  });

  test('production options require the typed Routed deployment path', () async {
    final deployment =
        AuthDeploymentPresets.secureSessionProduction<EngineContext>(
          store: _OpaqueDurableStore(),
          providers: const <AuthProvider>[],
          boundary: AuthProductionBoundary(
            trustedOrigins: [Uri.parse('https://app.example.com')],
            proxyPolicy: const AuthProxyPolicy.direct(),
          ),
          lifecycleDelivery:
              const AuthLifecycleDelivery<EngineContext>.disabled(),
          rateLimiter: _AllowAllRateLimiter(),
          requireVerifiedEmail: true,
        );
    final engine = testEngine(providers: [AuthServiceProvider()]);
    addTearDown(engine.close);
    engine.container.instance<AuthOptions<EngineContext>>(deployment.options);

    await expectLater(
      engine.initialize(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('typed AuthDeployment'),
        ),
      ),
    );
    expect(engine.container.has<AuthManager>(), isFalse);
  });

  test('AuthRuntime rejects callback-backed test stores', () {
    final options = AuthOptions<EngineContext>(
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      providers: const <AuthProvider>[],
    );

    expect(
      () => AuthRuntime<EngineContext>(
        options: options,
        store: CallbackAuthStore(),
      ),
      throwsArgumentError,
    );
  });
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
