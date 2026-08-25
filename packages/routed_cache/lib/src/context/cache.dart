/// Context extensions for using `server_cache` from a Routed request.
///
/// Configure a typed manager with `withCacheManager`, then use `ContextCache`
/// from handlers to read and write named stores.
library;

import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:server_cache/server_cache.dart';

/// Alias for the typed server cache manager used by [ContextCache].
///
/// Register concrete stores on this manager before passing it to
/// `withCacheManager`.
typedef CacheManager = DataCacheManager;

/// Adds cache operations to [EngineContext].
///
/// The helpers use the manager's default store unless a named `store` is
/// supplied. `getCache` has pull semantics: it reads and then removes the
/// entry.
extension ContextCache on EngineContext {
  /// The cache manager configured for this request's container.
  ///
  /// Configure it with `withCacheManager` or register a compatible manager in
  /// the request container. Throws a [StateError] when no cache manager has
  /// been registered.
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
  /// manager's default store is used. A non-positive [seconds] value requests
  /// a non-expiring entry from the underlying repository.
  ///
  /// ```dart
  /// await ctx.cache('profile:42', {'name': 'Ada'}, 300);
  /// await ctx.cache('sessions:42', session, 900, store: 'sessions');
  /// ```
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
  /// This is a one-shot read suitable for queues, one-time tokens, and other
  /// values that should not remain available after retrieval. If [store] is
  /// omitted, the manager's default store is used.
  FutureOr<dynamic> getCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .pull(key);
  }

  /// Removes [key] from the selected cache store.
  ///
  /// Returns the backend's result for the removal. If [store] is omitted, the
  /// manager's default store is used.
  FutureOr<bool> removeCache(String key, {String? store}) {
    return cacheManager
        .store(store ?? cacheManager.getDefaultStoreName())
        .forget(key);
  }

  /// Increments the numeric value stored under [key] by [value].
  ///
  /// The default [value] is `1`. If [store] is omitted, the manager's default
  /// store is used.
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
  /// The default [value] is `1`. If [store] is omitted, the manager's default
  /// store is used.
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
  /// The [ttl] may be a [Duration] or an integer number of seconds. The
  /// no-argument [callback] is invoked only when the key is missing, and its
  /// result is stored before it is returned. If [store] is omitted, the
  /// manager's default store is used.
  ///
  /// ```dart
  /// final value = await ctx.rememberCache(
  ///   'account:42',
  ///   const Duration(minutes: 5),
  ///   () => loadAccount(),
  /// );
  /// ```
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
  /// The no-argument [callback] is invoked only when the key is missing. If
  /// [store] is omitted, the manager's default store is used.
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
