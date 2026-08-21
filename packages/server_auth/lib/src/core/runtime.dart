import 'authentication_methods.dart';
import 'plugin.dart';
import 'options.dart';
import 'providers.dart'
    show AuthProvider, AuthProviderType, validateAuthProviderConfiguration;
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
    providers = List<AuthProvider>.unmodifiable(<AuthProvider>[
      ...options.providers,
      ...this.plugins.whereType<AuthProvider>(),
    ]);
    validateAuthProviderConfiguration(providers);
    authenticationMethods = AuthAuthenticationMethodService(
      store: this.store,
      contributors: <AuthAuthenticationMethodInventoryContributor>[
        _AuthAccountAuthenticationMethodInventory(
          this.store.accounts,
          activeProviderIds: {
            for (final provider in providers)
              if (provider.type == AuthProviderType.oauth ||
                  provider.type == AuthProviderType.oidc)
                provider.id,
          },
        ),
        ...options.providers
            .map(
              (provider) => provider.authenticationMethodInventory(this.store),
            )
            .whereType<AuthAuthenticationMethodInventoryContributor>(),
      ],
      historicalAuthenticationMethodNamespaces:
          options.historicalAuthenticationMethodNamespaces,
    );
    registry = AuthServerPluginRegistry<TContext>(
      store: this.store,
      authenticationMethods: authenticationMethods,
      passwordHasher: options.passwordHasher,
      passwordPolicy: options.passwordPolicy,
      sessionStrategy: options.sessionStrategy,
      historicalUserDataNamespaces: options.historicalUserDataNamespaces,
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

  /// Providers contributed by core options and provider plugins.
  late final List<AuthProvider> providers;

  /// Atomic inventory and mutation boundary shared by all auth methods.
  late final AuthAuthenticationMethodService authenticationMethods;

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

final class _AuthAccountAuthenticationMethodInventory
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  _AuthAccountAuthenticationMethodInventory(
    this.store, {
    required Set<String> activeProviderIds,
  }) : activeProviderIds = Set<String>.unmodifiable(activeProviderIds);

  final AuthAccountStore store;
  final Set<String> activeProviderIds;

  @override
  String get authenticationMethodNamespace => 'oauth';

  @override
  Object get authenticationMethodStore => store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.oauthProvider,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async => AuthAuthenticationMethodSnapshot.complete(
    (await store.listForUser(userId)).map(
      (account) => AuthAuthenticationMethod.oauthProvider(
        providerId: account.providerId,
        providerAccountId: account.providerAccountId,
        canAuthenticate: activeProviderIds.contains(account.providerId),
      ),
    ),
  );
}
