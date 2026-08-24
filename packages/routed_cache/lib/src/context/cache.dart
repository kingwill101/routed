import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:server_cache/server_cache.dart';

/// Alias for the server cache manager exposed through [ContextCache].
typedef CacheManager = DataCacheManager;

/// Adds cache operations to [EngineContext].
extension ContextCache on EngineContext {
  /// The cache manager configured for this request's container.
  ///
  /// Throws a [StateError] when no cache manager has been registered.
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

  /// Stores [value] under [key] for [seconds].
  ///
  /// Returns whether the store accepted the value. If [store] is omitted, the
  /// manager's default store is used.
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

  /// Returns and removes the value stored under [key].
  ///
  /// If [store] is omitted, the manager's default store is used.
  FutureOr<dynamic> getCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .pull(key);
  }

  /// Removes [key] from the selected cache store.
  ///
  /// Returns whether an entry was removed. If [store] is omitted, the
  /// manager's default store is used.
  FutureOr<bool> removeCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .forget(key);
  }

  /// Increments the numeric value stored under [key] by [value].
  ///
  /// If [store] is omitted, the manager's default store is used.
  FutureOr<dynamic> incrementCache(
    String key, [
    dynamic value = 1,
    String? store,
  ]) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .increment(key, value);
  }

  /// Decrements the numeric value stored under [key] by [value].
  ///
  /// If [store] is omitted, the manager's default store is used.
  FutureOr<dynamic> decrementCache(
    String key, [
    dynamic value = 1,
    String? store,
  ]) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .decrement(key, value);
  }

  /// Stores [value] under [key] without an expiration.
  ///
  /// Returns whether the store accepted the value. If [store] is omitted, the
  /// manager's default store is used.
  FutureOr<bool> cacheForever(String key, dynamic value, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .forever(key, value);
  }

  /// Returns the cached value or computes and stores it for [ttl].
  ///
  /// The [callback] is invoked only when the key is missing. If [store] is
  /// omitted, the manager's default store is used.
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

  /// Returns the cached value or computes and stores it indefinitely.
  ///
  /// The [callback] is invoked only when the key is missing. If [store] is
  /// omitted, the manager's default store is used.
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
