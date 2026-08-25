/// Typed Routed integration for the framework-neutral `server_cache` runtime.
///
/// Configure a [DataCacheManager] during application composition, then attach
/// it to the engine with [withCacheManager]. Request handlers can use the
/// `ContextCache` helpers without knowing which `Store` implementation backs
/// the selected cache name.
///
/// ```dart
/// final cache = DataCacheManager()
///   ..registerStore('default', ArrayStore());
///
/// final engine = Engine(
///   options: [withCacheManager(cache)],
/// )..get('/greeting', (ctx) async {
///   await ctx.cache('greeting', 'hello', 60);
///   return ctx.json({'value': await ctx.getCache('greeting')});
/// });
/// ```
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
///
/// ```dart
/// final cache = DataCacheManager()
///   ..registerStore('default', ArrayStore());
/// final cacheOption = withCacheManager(cache);
/// ```
EngineOpt withCacheManager(DataCacheManager manager) => withService(manager);

/// Container key used by [CacheEngineContext] and [cacheMiddleware].
const cacheStoreKey = ContextKey<Store>('routed.cache.store');

/// Provides access to a request's configured low-level cache store.
extension CacheEngineContext on EngineContext {
  /// The low-level store attached to this request by [cacheMiddleware].
  ///
  /// This is useful when a handler needs backend-specific operations. Prefer
  /// `ContextCache` for portable cache reads and writes.
  Store get cacheStore => mustGet<Store>(cacheStoreKey.name);

  /// Whether this request has a low-level store attached by [cacheMiddleware].
  bool get hasCache => get<Store>(cacheStoreKey.name) != null;
}

/// Attaches [store] to each request before the next middleware runs.
///
/// This middleware exposes the low-level store through [CacheEngineContext].
/// It is independent of [withCacheManager], which configures the manager used
/// by the higher-level `ContextCache` helpers.
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
  ///
  /// The current configuration has no additional constraints because [store]
  /// is required to be a concrete [Store] before this method is called.
  @override
  void validate(ConfigValidationContext context) {}
}

/// Registers a configured cache store with the Routed service container.
class RoutedCacheProvider extends ServiceProvider
    with ProvidesTypedConfiguration<CacheConfig> {
  /// Uses an in-memory [ArrayStore] suitable for tests and light apps.
  RoutedCacheProvider([CacheConfig? configuration])
    : configuration = configuration ?? CacheConfig();

  /// Configuration used to register the cache store.
  @override
  final CacheConfig configuration;

  /// Registers the configured [Store] as a container singleton.
  @override
  void register(Container container) {
    container.singleton<Store>((_) async => configuration.store);
  }

  /// Completes provider boot without additional cache-specific work.
  @override
  Future<void> boot(Container container) async {}
}

/// Registers the cache provider factory in the shared registry.
///
/// Applications that construct providers explicitly do not need to call this
/// function. Call it when the application uses the shared [ProviderRegistry]
/// discovery flow.
void registerRoutedCacheProviders() {
  ProviderRegistry.instance.register(
    'routed.cache',
    factory: RoutedCacheProvider.new,
    description: 'In-memory cache store and context helpers.',
  );
}
