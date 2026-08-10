import 'dart:async';

import 'package:routed_core/routed_core.dart';
import 'package:routed_cache/routed_cache.dart';
import 'package:server_cache/server_cache.dart';

void main() async {
  final cacheManager = DataCacheManager()
    ..registerStore('array', {'driver': 'array', 'serialize': false});

  final engine = Engine(
    options: [withCacheManager(cacheManager)],
  );

  engine.get('/cache', (ctx) async {
    await ctx.cache('key', 'value', 60);
    final before = await ctx.getCache('key');
    final removed = await ctx.removeCache('key');
    final after = await ctx.getCache('key');
    return ctx.json({'before': before, 'removed': removed, 'after': after});
  });

  engine.get('/forever', (ctx) async {
    await ctx.cacheForever('forever-key', 'permanent');
    final value = await ctx.pullCache('forever-key');
    return ctx.json({'value': value});
  });

  // For demo, we avoid actually serving; just show helpers compile.
  // To serve: await engine.serve(port: 8080);
  print('routed_cache example: Engine configured with DataCacheManager(array).');
  print('Routes: GET /cache, GET /forever');
  await engine.close();
}

// Helper alias: getCache uses pull semantics
extension _PullAlias on EngineContext {
  FutureOr<dynamic> pullCache(String key, {String? store}) => getCache(key, store: store);
}
