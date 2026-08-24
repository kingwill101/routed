import 'package:server_cache/src/tag_set.dart';
import 'package:server_cache/src/tagged_cache.dart';
import 'package:server_contracts/server_contracts.dart';

/// An abstract class that provides tagging capabilities for cache stores.
///
/// The `TaggableStore` class allows cache stores to be tagged with specific
/// identifiers, enabling more granular control over cache invalidation and
/// retrieval. This is particularly useful in scenarios where you want to
/// group cache items and invalidate them based on certain tags.
abstract class TaggableStore {
  /// Creates a `TaggedCache` instance with the specified tags.
  ///
  /// The `tags` method takes a list of tag names and returns a `TaggedCache`
  /// instance. This instance can be used to perform cache operations that
  /// are scoped to the specified tags.
  ///
  /// - Parameters:
  ///   - names: A list of strings representing the tag names.
  ///
  /// - Returns: A `TaggedCache` instance that is associated with the specified
  ///   tags.
  ///
  /// Example usage:
  /// ```dart
  /// var taggedCache = taggableStore.tags(['user', 'session']);
  /// taggedCache.put('key', 'value');
  /// ```
  TaggedCache tags(List<String> names) {
    return TaggedCache(this as Store, TagSet(this as Store, names));
  }
}
