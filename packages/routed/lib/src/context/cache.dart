part of 'context.dart';

extension ContextCache on EngineContext {
  CacheManager get cacheManager =>
      _engine?.config.cacheManager ??
      (throw StateError('Cache manager not configured'));

  Future<bool> cache(String key, dynamic value, int seconds,
      {String? store}) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .put(key, value, Duration(seconds: seconds));
  }

  Future<dynamic> getCache(String key, {String? store}) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .pull(key);
  }

  Future<bool> removeCache(String key, {String? store}) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .forget(key);
  }

  Future<dynamic> incrementCache(String key,
      [dynamic value = 1, String? store]) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .increment(key, value);
  }

  Future<dynamic> decrementCache(String key,
      [dynamic value = 1, String? store]) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .decrement(key, value);
  }

  Future<bool> cacheForever(String key, dynamic value, {String? store}) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .forever(key, value);
  }

  Future<dynamic> rememberCache(String key, dynamic ttl, Function callback,
      {String? store}) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .remember(key, ttl, callback);
  }

  Future<dynamic> rememberCacheForever(String key, Function callback,
      {String? store}) async {
    return await cacheManager
        .store(store ?? cacheManager.getDefaultDriver())
        .rememberForever(key, callback);
  }
}
