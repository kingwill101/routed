library;

import 'package:routed_core/providers.dart' show ProviderRegistry;
import 'package:routed_core/routed_core.dart' hide Store;
import 'package:server_cache/server_cache.dart' show ArrayStore;
import 'package:server_contracts/server_contracts.dart' show Store;

export 'src/context/cache.dart';
export 'src/events/cache_events.dart';

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

class RoutedCacheProvider extends ServiceProvider {
  /// Uses an in-memory [ArrayStore] suitable for tests and light apps.
  RoutedCacheProvider([Store? store]) : store = store ?? ArrayStore();

  final Store store;

  @override
  void register(Container container) {
    container.singleton<Store>((_) async => store);
  }

  @override
  Future<void> boot(Container container) async {}
}

/// Registers `routed.cache` for `http.providers` resolution.
void registerRoutedCacheProviders() {
  ProviderRegistry.instance.register(
    'routed.cache',
    factory: RoutedCacheProvider.new,
    description: 'In-memory cache store and context helpers.',
  );
}
