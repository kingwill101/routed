/// Framework-neutral cache stores, repositories, locks, and typed factories.
///
/// Use a `Store` when you need the low-level backend contract, or wrap one in
/// a `Repository` when you want TTLs expressed as `Duration` values, key
/// prefixes, and cache instrumentation. `DataCacheManager` keeps named stores
/// and their repositories together during application composition.
///
/// The package includes in-memory, file, Redis, and no-op stores. Store
/// construction is typed: pair a `StoreFactory` with its matching
/// `StoreConfiguration` instead of passing an unstructured configuration map.
///
/// ```dart
/// final cache = DataCacheManager()
///   ..registerStoreFactory(
///     'sessions',
///     ArrayStoreFactory(),
///     const ArrayStoreConfiguration(serialize: true),
///   );
///
/// final sessions = cache.store('sessions');
/// await sessions.put('user:42', {'active': true}, const Duration(minutes: 5));
/// ```
library;

export 'src/array_store.dart';
export 'src/array_store_factory.dart';
export 'src/cache.dart';
export 'src/file_store.dart';
export 'src/file_store_factory.dart';
export 'src/null_store.dart';
export 'src/redis_store.dart';
export 'src/redis_store_factory.dart';
export 'src/repository.dart';
export 'src/store_factory.dart';
export 'src/tagged_cache.dart';
