/// Routed integration for the framework-neutral `server_cache` runtime.
library;

import 'package:routed_core/routed_core.dart' hide Store;
import 'package:server_cache/server_cache.dart'
    show ArrayStore, DataCacheManager;
import 'package:server_contracts/server_contracts.dart' show Store;

export 'package:server_cache/server_cache.dart';
export 'src/context/cache.dart';
export 'src/events/cache_events.dart';

/// Binds an application-owned [DataCacheManager] to the request container.
///
/// Cache-specific wiring lives in `routed_cache`; `routed_core` deliberately
/// has no dependency on the cache runtime.
EngineOpt withCacheManager(DataCacheManager manager) => withService(manager);

/// Container key used by [CacheEngineContext] and [cacheMiddleware].
const cacheStoreKey = ContextKey<Store>('routed.cache.store');

/// Provides access to a request's configured low-level cache store.
extension CacheEngineContext on EngineContext {
  /// The low-level store attached to this request.
  Store get cacheStore => mustGet<Store>(cacheStoreKey.name);

  /// Whether this request has a low-level cache store attached.
  bool get hasCache => get<Store>(cacheStoreKey.name) != null;
}

/// Attaches [store] to each request before the next middleware runs.
Middleware cacheMiddleware(Store store) {
  return (ctx, next) {
    ctx.set(cacheStoreKey.name, store);
    return next();
  };
}

/// Typed configuration for the Routed cache integration.
class CacheConfig implements ValidatableConfiguration {
  /// Creates a cache configuration using an [ArrayStore] by default.
  CacheConfig({Store? store}) : store = store ?? ArrayStore();

  /// Store registered in the request container by [RoutedCacheProvider].
  final Store store;

  /// Validates this configuration.
  @override
  void validate(ConfigValidationContext context) {}
}

/// Registers a configured cache store with the Routed service container.
class RoutedCacheProvider extends ServiceProvider
    with ProvidesTypedConfiguration<CacheConfig> {
  /// Uses an in-memory [ArrayStore] suitable for tests and light apps.
  RoutedCacheProvider([CacheConfig? configuration])
    : configuration = configuration ?? CacheConfig();

  @override
  final CacheConfig configuration;

  @override
  void register(Container container) {
    container.singleton<Store>((_) async => configuration.store);
  }

  @override
  Future<void> boot(Container container) async {}
}

/// Registers the cache provider factory in the shared registry.
void registerRoutedCacheProviders() {
  ProviderRegistry.instance.register(
    'routed.cache',
    factory: RoutedCacheProvider.new,
    description: 'In-memory cache store and context helpers.',
  );
}
