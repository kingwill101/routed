import 'package:server_contracts/server_contracts.dart';

import 'null_store.dart';
import 'store_factory.dart';

/// Typed options for [NullStore].
class NullStoreConfiguration implements StoreConfiguration {
  const NullStoreConfiguration();
}

class NullStoreFactory implements StoreFactory<NullStoreConfiguration> {
  @override
  Store create(NullStoreConfiguration configuration) => NullStore();
}
