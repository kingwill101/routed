import 'package:server_cache/src/null_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for [NullStore].
class NullStoreConfiguration implements StoreConfiguration {
  /// Creates options for a non-persistent null store.
  const NullStoreConfiguration();
}

/// Creates [NullStore] instances.
class NullStoreFactory implements StoreFactory<NullStoreConfiguration> {
  @override
  Store create(NullStoreConfiguration configuration) => NullStore();
}
