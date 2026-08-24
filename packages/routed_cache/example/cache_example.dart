import 'dart:async';
import 'dart:io';

import 'package:routed_cache/routed_cache.dart';
import 'package:routed_core/routed_core.dart';

void main() async {
  final cacheManager = DataCacheManager()..registerStore('array', ArrayStore());

  final engine = Engine(options: [withCacheManager(cacheManager)])
    ..get('/cache', (ctx) async {
      await ctx.cache('key', 'value', 60);
      final before = await ctx.getCache('key');
      final removed = await ctx.removeCache('key');
      final after = await ctx.getCache('key');
      return ctx.json({'before': before, 'removed': removed, 'after': after});
    })
    ..get('/forever', (ctx) async {
      await ctx.cacheForever('forever-key', 'permanent');
      final value = await ctx.pullCache('forever-key');
      return ctx.json({'value': value});
    });

  // For demo, we avoid actually serving; just show helpers compile.
  // To serve: await engine.serve(port: 8080);
  stdout
    ..writeln(
      'routed_cache example: Engine configured with DataCacheManager(array).',
    )
    ..writeln('Routes: GET /cache, GET /forever');
  await engine.close();
}

// Helper alias: getCache uses pull semantics
extension _PullAlias on EngineContext {
  FutureOr<dynamic> pullCache(String key, {String? store}) =>
      getCache(key, store: store);
}
