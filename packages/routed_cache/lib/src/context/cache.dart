import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:server_cache/server_cache.dart';

typedef CacheManager = DataCacheManager;

extension ContextCache on EngineContext {
  CacheManager get cacheManager {
    if (container.has<CacheManager>()) {
      return container.get<CacheManager>();
    }
    if (container.has<dynamic>()) {
      final dynamic m = container.get<dynamic>();
      if (m is CacheManager) return m;
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
        .store(store ?? cacheManager.getDefaultStoreName())
        .put(key, value, Duration(seconds: seconds));
  }

  FutureOr<dynamic> getCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .pull(key);
  }

  FutureOr<bool> removeCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .forget(key);
  }

  FutureOr<dynamic> incrementCache(
    String key, [
    dynamic value = 1,
    String? store,
  ]) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .increment(key, value);
  }

  FutureOr<dynamic> decrementCache(
    String key, [
    dynamic value = 1,
    String? store,
  ]) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .decrement(key, value);
  }

  FutureOr<bool> cacheForever(String key, dynamic value, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .forever(key, value);
  }

  FutureOr<dynamic> rememberCache(
    String key,
    dynamic ttl,
    Function callback, {
    String? store,
  }) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .remember(key, ttl, callback);
  }

  FutureOr<dynamic> rememberCacheForever(
    String key,
    Function callback, {
    String? store,
  }) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .rememberForever(key, callback);
  }
}
