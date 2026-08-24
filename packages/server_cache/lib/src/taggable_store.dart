import 'package:server_cache/src/tag_set.dart';
import 'package:server_cache/src/tagged_cache.dart';
import 'package:server_contracts/server_contracts.dart';

/// Mixin-like base class that exposes tag-scoped cache repositories.
///
/// A concrete store extends this class when tagged keys should be isolated by
/// version identifiers. The implementation assumes the concrete object also
/// implements `Store`; it is intended for the package's cache stores.
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
  /// Example:
  /// ```dart
  /// final taggedCache = taggableStore.tags(['user', 'session']);
  /// await taggedCache.put('key', 'value');
  /// ```
  TaggedCache tags(List<String> names) {
    return TaggedCache(this as Store, TagSet(this as Store, names));
  }
}
