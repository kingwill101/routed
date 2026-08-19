import 'package:server_contracts/server_contracts.dart';

import 'redis_store.dart';
import 'store_factory.dart';

/// Typed options for [RedisStore].
class RedisStoreConfiguration implements StoreConfiguration {
  const RedisStoreConfiguration({
    this.url,
    this.host,
    this.port,
    this.password,
    this.database,
  });

  final Uri? url;
  final String? host;
  final int? port;
  final String? password;
  final int? database;
}

/// Creates Redis-backed stores from [RedisStoreConfiguration].
class RedisStoreFactory implements StoreFactory<RedisStoreConfiguration> {
  @override
  Store create(RedisStoreConfiguration configuration) {
    var host = '127.0.0.1';
    var port = 6379;
    String? password;
    int? database;

    final url = configuration.url;
    if (url != null) {
      if (url.host.isNotEmpty) host = url.host;
      if (url.port != 0) port = url.port;
      if (url.userInfo.isNotEmpty) {
        final separator = url.userInfo.indexOf(':');
        final rawPassword = separator == -1
            ? url.userInfo
            : url.userInfo.substring(separator + 1);
        if (rawPassword.isNotEmpty) password = Uri.decodeComponent(rawPassword);
      }
      if (url.pathSegments.isNotEmpty) {
        database = int.tryParse(url.pathSegments.last);
      }
      database = int.tryParse(url.queryParameters['db'] ?? '') ?? database;
    }

    return RedisStore(
      configuration.host ?? host,
      configuration.port ?? port,
      password: configuration.password ?? password,
      db: configuration.database ?? database,
    );
  }
}
