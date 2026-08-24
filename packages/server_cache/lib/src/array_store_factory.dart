import 'package:server_cache/src/array_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for creating an [ArrayStore].
///
/// The option is intentionally small because an array store is scoped to the
/// current Dart isolate and has no external connection to configure.
class ArrayStoreConfiguration implements StoreConfiguration {
  /// Creates in-memory store options.
  ///
  /// When [serialize] is `true`, values are JSON-encoded before they are
  /// stored and decoded when they are read. This is useful when exercising the
  /// same serialization boundary as a persistent store, but values must still
  /// be JSON-compatible.
  const ArrayStoreConfiguration({this.serialize = false});

  /// Whether values are JSON-encoded before storage.
  final bool serialize;
}

/// Creates isolate-local [ArrayStore] instances from typed options.
class ArrayStoreFactory implements StoreFactory<ArrayStoreConfiguration> {
  /// Creates an in-memory store using [configuration].
  @override
  Store create(ArrayStoreConfiguration configuration) =>
      ArrayStore(configuration.serialize);
}
