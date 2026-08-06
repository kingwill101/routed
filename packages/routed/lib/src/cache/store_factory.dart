import 'package:routed/src/contracts/cache/store.dart';

/// An abstract factory for creating [Store] instances.
///
/// Implementations of this factory are responsible for parsing a given
/// configuration map and producing a concrete [Store] implementation
/// based on that configuration.
///
/// This allows for flexible and dynamic creation of different types
/// of stores without hardcoding their instantiation.
abstract class StoreFactory {
  /// Creates a [Store] instance using the provided configuration [config].
  ///
  /// The [config] map typically contains parameters specific to the type
  /// of store being created, such as `type`, `path`, `host`, etc.
  ///
  /// Example:
  /// ```dart
  /// // Assuming 'MyFileStoreFactory' and 'MyMemoryStoreFactory' are
  /// // concrete implementations of StoreFactory.
  ///
  /// // Create a file-based store
  /// var fileFactory = MyFileStoreFactory();
  /// var fileStore = fileFactory.create({
  ///   'type': 'file',
  ///   'path': '/data/cache.json',
  /// });
  ///
  /// // Create an in-memory store
  /// var memoryFactory = MyMemoryStoreFactory();
  /// var memoryStore = memoryFactory.create({
  ///   'type': 'memory',
  ///   // In-memory stores might not need specific config,
  ///   // or could take a 'name' for identification.
  ///   'name': 'session_cache',
  /// });
  /// ```
  ///
  /// Throws an [ArgumentError] if the [config] is invalid or if it
  /// specifies a store type that cannot be created by this factory.
  ///
  /// Returns a new [Store] instance.
  Store create(Map<String, dynamic> config);
}
