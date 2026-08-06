library;

import 'package:routed/routed.dart' hide Store;
import 'package:server_contracts/server_contracts.dart' show Store;

const cacheStoreKey = ContextKey<Store>('routed.cache.store');

extension CacheEngineContext on EngineContext {
  Store get cache => mustGet<Store>(cacheStoreKey.name);
  bool get hasCache => get<Store>(cacheStoreKey.name) != null;
}

Middleware cacheMiddleware(Store store) {
  return (ctx, next) {
    ctx.set(cacheStoreKey.name, store);
    return next();
  };
}

class RoutedCacheProvider extends ServiceProvider {
  RoutedCacheProvider(this.store);
  final Store store;
  @override
  void register(Container container) {
    container.singleton<Store>((_) async => store);
  }

  @override
  Future<void> boot(Container container) async {}
}
