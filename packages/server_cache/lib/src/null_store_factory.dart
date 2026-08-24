import 'package:server_cache/src/null_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for creating a [NullStore].
class NullStoreConfiguration implements StoreConfiguration {
  /// Creates options for a non-persistent null store.
  const NullStoreConfiguration();
}

/// Creates [NullStore] instances from typed options.
class NullStoreFactory implements StoreFactory<NullStoreConfiguration> {
  /// Creates a no-op store from [configuration].
  @override
  Store create(NullStoreConfiguration configuration) => NullStore();
}
