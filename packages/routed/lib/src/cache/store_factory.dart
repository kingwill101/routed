import 'package:routed/src/contracts/cache/store.dart';

abstract class StoreFactory {
  // Creates a Store instance using the provided configuration.
  Store create(Map<String, dynamic> config);
}
