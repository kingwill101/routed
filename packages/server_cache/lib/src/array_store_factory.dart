import 'package:server_cache/src/array_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for [ArrayStore].
class ArrayStoreConfiguration implements StoreConfiguration {
  /// Creates in-memory store options.
  ///
  /// When [serialize] is true, values are encoded before they are stored.
  const ArrayStoreConfiguration({this.serialize = false});

  /// Whether values should be serialized before storage.
  final bool serialize;
}

/// Creates in-memory [ArrayStore] instances.
class ArrayStoreFactory implements StoreFactory<ArrayStoreConfiguration> {
  @override
  Store create(ArrayStoreConfiguration configuration) =>
      ArrayStore(configuration.serialize);
}
