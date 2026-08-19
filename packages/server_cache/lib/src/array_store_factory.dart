import 'package:server_contracts/server_contracts.dart';

import 'array_store.dart';
import 'store_factory.dart';

/// Typed options for [ArrayStore].
class ArrayStoreConfiguration implements StoreConfiguration {
  const ArrayStoreConfiguration({this.serialize = false});

  final bool serialize;
}

class ArrayStoreFactory implements StoreFactory<ArrayStoreConfiguration> {
  @override
  Store create(ArrayStoreConfiguration configuration) =>
      ArrayStore(configuration.serialize);
}
