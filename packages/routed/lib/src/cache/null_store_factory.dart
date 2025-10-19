import 'package:routed/src/cache/null_store.dart';
import 'package:routed/src/contracts/cache/store.dart';

import 'store_factory.dart';

class NullStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) => NullStore();
}
