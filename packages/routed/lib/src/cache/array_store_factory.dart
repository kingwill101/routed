import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/cache/array_store.dart';
import 'store_factory.dart';

class ArrayStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    // Create an ArrayStore using configuration values.
    return ArrayStore(config['serialize'] ?? false);
  }
}
