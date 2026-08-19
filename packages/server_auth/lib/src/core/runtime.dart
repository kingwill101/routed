import 'feature.dart';
import 'options.dart';
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
    Iterable<AuthFeature<TContext>> features = const [],
    bool requireDurableStore = false,
  }) : store = store ?? options.store,
       features = List<AuthFeature<TContext>>.unmodifiable([
         ...options.features,
         ...features,
       ]) {
    if (store is CallbackAuthStore) {
      throw ArgumentError(
        'CallbackAuthStore is a test utility and cannot back AuthRuntime.',
      );
    }
    if (requireDurableStore) requireDurableStoreOrThrow();
    registry = AuthFeatureRegistry<TContext>(store: this.store);
    for (final feature in this.features) {
      registry.register(feature);
    }
  }

  final AuthOptions<TContext> options;

  /// Typed domain stores used by auth features.
  final AuthStore store;

  /// The features configured for this runtime.
  final List<AuthFeature<TContext>> features;

  /// Registry of features active in this runtime.
  late final AuthFeatureRegistry<TContext> registry;

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

  AuthFeature<TContext>? feature(String id) => registry.find(id);

  bool hasFeature(String id) => registry.contains(id);
}
