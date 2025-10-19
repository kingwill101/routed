import 'package:routed/src/events/event.dart';

/// Base class for all cache-related events.
///
/// Each event targets a cache [store] and a [key]. Subclasses describe the
/// exact cache interaction that occurred.
sealed class CacheEvent extends Event {
  /// Creates a cache event for the given [store] and [key].
  CacheEvent({required this.store, required this.key});

  /// Name of the cache store that emitted this event.
  final String store;

  /// Cache entry key this event refers to.
  final String key;
}

/// An event emitted when a cache lookup succeeds.
final class CacheHitEvent extends CacheEvent {
  /// Creates a cache-hit event for the given [store] and [key].
  CacheHitEvent({required super.store, required super.key});
}

/// An event emitted when a cache lookup fails.
final class CacheMissEvent extends CacheEvent {
  /// Creates a cache-miss event for the given [store] and [key].
  CacheMissEvent({required super.store, required super.key});
}

/// An event emitted when a new value is written to the cache.
final class CacheWriteEvent extends CacheEvent {
  /// Creates a cache-write event.
  ///
  /// If provided, [ttl] specifies how long the written value should live
  /// before it expires.
  CacheWriteEvent({required super.store, required super.key, this.ttl});

  /// Optional time-to-live for the written value.
  final Duration? ttl;
}

/// An event emitted when a cache entry is explicitly removed.
final class CacheForgetEvent extends CacheEvent {
  /// Creates a cache-forget event for the given [store] and [key].
  CacheForgetEvent({required super.store, required super.key});
}
