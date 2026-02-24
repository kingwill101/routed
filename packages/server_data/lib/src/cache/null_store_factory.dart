import 'package:server_contracts/server_contracts.dart';

import 'null_store.dart';
import 'store_factory.dart';

class NullStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) => NullStore();
}
