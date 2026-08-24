import 'package:server_cache/src/redis_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for creating a [RedisStore].
class RedisStoreConfiguration implements StoreConfiguration {
  /// Creates Redis connection options.
  ///
  /// A supplied [url] provides the initial host, port, password, and database.
  /// Explicit fields override the corresponding values parsed from the URL.
  /// When neither source provides a host or port, the factory uses
  /// `127.0.0.1:6379`.
  const RedisStoreConfiguration({
    this.url,
    this.host,
    this.port,
    this.password,
    this.database,
  });

  /// Optional Redis URL used as the connection source.
  ///
  /// The database may be specified in the final path segment or with the
  /// `db` query parameter. The query parameter wins when both are present.
  final Uri? url;

  /// Redis hostname or address, overriding [url].
  final String? host;

  /// Redis TCP port, overriding [url].
  final int? port;

  /// Redis authentication password, overriding credentials in [url].
  final String? password;

  /// Redis database number, overriding the database selected by [url].
  final int? database;
}

/// Creates Redis-backed stores from typed [RedisStoreConfiguration] options.
class RedisStoreFactory implements StoreFactory<RedisStoreConfiguration> {
  /// Creates a Redis store using [configuration].
  ///
  /// The factory does not connect to Redis until the returned store performs
  /// an operation. Connection and authentication errors therefore occur at
  /// first use rather than during factory composition.
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
