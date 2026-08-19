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

const cacheStoreKey = ContextKey<Store>('routed.cache.store');

extension CacheEngineContext on EngineContext {
  Store get cacheStore => mustGet<Store>(cacheStoreKey.name);
  bool get hasCache => get<Store>(cacheStoreKey.name) != null;
}

Middleware cacheMiddleware(Store store) {
  return (ctx, next) {
    ctx.set(cacheStoreKey.name, store);
    return next();
  };
}

/// Typed configuration for the cache integration.
class CacheConfig implements ValidatableConfiguration {
  CacheConfig({Store? store}) : store = store ?? ArrayStore();

  final Store store;

  @override
  void validate(ConfigValidationContext context) {}
}

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
