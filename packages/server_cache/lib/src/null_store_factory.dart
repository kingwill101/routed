import 'package:server_contracts/server_contracts.dart';

import 'null_store.dart';
import 'store_factory.dart';

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
