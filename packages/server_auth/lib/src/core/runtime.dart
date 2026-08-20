import 'plugin.dart';
import 'options.dart';
import 'runtime_posture.dart';
import 'store.dart';

/// Composed authentication runtime for one application.
///
/// [AuthRuntime] is the kernel boundary between typed auth capabilities and a
/// framework integration. Persistence is taken from [AuthOptions.store]
/// unless an explicit store is supplied.
class AuthRuntime<TContext> {
  AuthRuntime({
    required this.options,
    AuthStore? store,
    Iterable<AuthServerPlugin<TContext>> plugins = const [],
  }) : store = store ?? options.store,
       plugins = List<AuthServerPlugin<TContext>>.unmodifiable([
         ...options.plugins,
         ...plugins,
       ]) {
    if (store is CallbackAuthStore) {
      throw ArgumentError(
        'CallbackAuthStore is a test utility and cannot back AuthRuntime.',
      );
    }
    if (options.runtimeMode == AuthRuntimeMode.production) {
      options.requireProductionBoot();
      requireDurableStoreOrThrow();
    }
    registry = AuthServerPluginRegistry<TContext>(
      store: this.store,
      passwordHasher: options.passwordHasher,
      passwordPolicy: options.passwordPolicy,
      sessionStrategy: options.sessionStrategy,
    );
    for (final plugin in this.plugins) {
      registry.register(plugin);
    }
    registry.freeze();
  }

  final AuthOptions<TContext> options;

  /// Typed domain stores used by auth plugins.
  final AuthStore store;

  /// The plugins configured for this runtime.
  final List<AuthServerPlugin<TContext>> plugins;

  /// Registry of plugins active in this runtime.
  late final AuthServerPluginRegistry<TContext> registry;

  /// Throws when this runtime is backed by intentionally ephemeral storage.
  void requireDurableStoreOrThrow() {
    if (store is InMemoryAuthStore ||
        store is CallbackAuthStore ||
        options.storeMode == AuthStoreMode.ephemeral) {
      throw StateError(
        'Ephemeral auth storage is not allowed for production boot.',
      );
    }
  }

  AuthServerPlugin<TContext>? plugin(String id) => registry.find(id);

  bool hasPlugin(String id) => registry.contains(id);
}
