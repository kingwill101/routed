import 'package:server_contracts/server_contracts.dart';

import 'array_store.dart';
import 'store_factory.dart';

class ArrayStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    // Create an ArrayStore using configuration values.
    final dynamic serializeValue = config['serialize'];
    final bool serialize = serializeValue is bool ? serializeValue : false;
    return ArrayStore(serialize);
  }
}
