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

  test(
    'AuthServiceProvider can reject ephemeral storage during boot',
    () async {
      final options = AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const <AuthProvider>[],
      );
      final engine = testEngine(
        providers: [AuthServiceProvider(requireDurableStore: true)],
      );
      engine.container.instance<AuthOptions<EngineContext>>(options);

      expect(engine.initialize, throwsStateError);
    },
  );

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
        requireDurableStore: true,
      ),
      throwsArgumentError,
    );
  });
}
