import 'package:server_contracts/server_contracts.dart';

/// Typed configuration for a cache store.
abstract interface class StoreConfiguration {
  const StoreConfiguration();
}

/// Creates a [Store] from typed options.
///
/// Applications can keep store construction in a reusable adapter without
/// introducing a string-keyed configuration map into the cache runtime.
abstract interface class StoreFactory<T extends StoreConfiguration> {
  /// Creates a new store from [configuration].
  Store create(T configuration);
}
