part of 'context.dart';

extension ContextCache on EngineContext {
  CacheManager get cacheManager {
    if (container.has<CacheManager>()) {
      return container.get<CacheManager>();
    }
    throw StateError('Cache manager not configured');
  }

  FutureOr<bool> cache(
    String key,
    dynamic value,
    int seconds, {
    String? store,
  }) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .put(key, value, Duration(seconds: seconds));
  }

  FutureOr<dynamic> getCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .pull(key);
  }

  FutureOr<bool> removeCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .forget(key);
  }

  FutureOr<dynamic> incrementCache(
    String key, [
    dynamic value = 1,
    String? store,
  ]) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .increment(key, value);
  }

  FutureOr<dynamic> decrementCache(
    String key, [
    dynamic value = 1,
    String? store,
  ]) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .decrement(key, value);
  }

  FutureOr<bool> cacheForever(String key, dynamic value, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .forever(key, value);
  }

  FutureOr<dynamic> rememberCache(
    String key,
    dynamic ttl,
    Function callback, {
    String? store,
  }) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .remember(key, ttl, callback);
  }

  FutureOr<dynamic> rememberCacheForever(
    String key,
    Function callback, {
    String? store,
  }) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .rememberForever(key, callback);
  }
}
