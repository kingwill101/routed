import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart';

void main() async {
  final databasePath =
      Platform.environment['DATABASE_PATH'] ?? 'storage/cache.sqlite';
  File(databasePath).absolute.parent.createSync(recursive: true);
  final database = await SqliteDatabase.connect(path: databasePath);
  final cache = OrmCacheStore(database);

  // Initialize the cache manager with a durable Ormed-backed store. The
  // migration is run by RoutedDatabaseProvider before requests are accepted.
  final cacheManager = CacheManager()..registerStore('database', cache);

  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders.where(
        (provider) => provider is! RoutedCacheProvider,
      ),
      RoutedCacheProvider(CacheConfig(store: cache)),
      RoutedDatabaseProvider(
        manager: DatabaseManager()..register('default', database),
        migrations: [cache.migration],
        migrateOnBoot: true,
      ),
    ],
    options: [withCacheManager(cacheManager)],
  );

  // Example route demonstrating basic cache operations
  engine.get('/cached-value', (ctx) async {
    // Try to get from cache first
    final value = await ctx.getCache('test-key');
    if (value != null) {
      return ctx.json({'value': value, 'from_cache': true});
    }

    // Set in cache and return
    final newValue = 'test-value';
    await ctx.cache('test-key', newValue, 60); // Cache for 60 seconds
    return ctx.json({'value': newValue, 'from_cache': false});
  });

  // Example route demonstrating increment/decrement operations
  engine.get('/counter', (ctx) async {
    // Initialize counter if not exists
    if (await ctx.getCache('counter') == null) {
      await ctx.cache('counter', 0, 60);
    }

    // Increment by 5, then decrement by 2
    await ctx.incrementCache('counter', 5);
    await ctx.decrementCache('counter', 2);

    final value = await ctx.getCache('counter');
    return ctx.json({'value': value});
  });

  // Example route demonstrating remember cache
  engine.get('/remember', (ctx) async {
    // This will only compute the value if it's not in cache
    final value = await ctx.rememberCache(
      'remembered-key',
      60,
      () => 'computed-value', // Expensive computation simulation
    );
    return ctx.json({'value': value});
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
