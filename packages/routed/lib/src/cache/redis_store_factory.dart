import 'package:routed/src/contracts/cache/store.dart';

import 'redis_store.dart';
import 'store_factory.dart';

class RedisStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    final normalized = <String, dynamic>{};
    config.forEach((key, value) {
      normalized[key.toString()] = value;
    });
    return RedisStore.fromConfig(normalized);
  }
}
