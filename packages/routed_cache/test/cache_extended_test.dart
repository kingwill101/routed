import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  CacheManager cacheManager = CacheManager()
    ..registerStore('array', {'driver': 'array', 'serialize': false});

  group('Cache extension — gap coverage', () {
    engineGroup(
      'cache gaps',
      options: [
        withCacheManager(cacheManager),
        (engine) {
          engine.get('/remove-cache', (ctx) async {
            await ctx.cache('to-remove', 'value', 60);
            final before = await ctx.getCache('to-remove');
            final removed = await ctx.removeCache('to-remove');
            final after = await ctx.getCache('to-remove');
            return ctx.json({
              'before': before,
              'removed': removed,
              'after': after,
            });
          });

          engine.get('/cache-forever', (ctx) async {
            final stored = await ctx.cacheForever('forever-key', 'permanent');
            final value = await ctx.getCache('forever-key');
            return ctx.json({'stored': stored, 'value': value});
          });

          engine.get('/remember-forever', (ctx) async {
            var computeCount = 0;
            final value1 = await ctx.rememberCacheForever('rf-key', () {
              computeCount++;
              return 'computed-once';
            });
            final value2 = await ctx.rememberCacheForever('rf-key', () {
              computeCount++;
              return 'should-not-recompute';
            });
            return ctx.json({
              'value1': value1,
              'value2': value2,
              'computeCount': computeCount,
            });
          });

          engine.get('/remove-nonexistent', (ctx) async {
            final removed = await ctx.removeCache('does-not-exist');
            return ctx.json({'removed': removed});
          });
        },
      ],
      define: (engine, client, tess) {
        tess('removeCache removes a cached value', (engine, client) async {
          final res = await client.getJson('/remove-cache');
          res
            ..assertStatus(200)
            ..assertJsonPath('before', 'value')
            ..assertJsonPath('removed', true)
            ..assertJsonPath('after', null);
        });

        tess('cacheForever stores without TTL', (engine, client) async {
          final res = await client.getJson('/cache-forever');
          res
            ..assertStatus(200)
            ..assertJsonPath('stored', true)
            ..assertJsonPath('value', 'permanent');
        });

        tess('rememberCacheForever computes once then caches', (
          engine,
          client,
        ) async {
          final res = await client.getJson('/remember-forever');
          res
            ..assertStatus(200)
            ..assertJsonPath('value1', 'computed-once')
            ..assertJsonPath('value2', 'computed-once');
        });

        tess('removeCache on nonexistent key returns true for array store', (
          engine,
          client,
        ) async {
          final res = await client.getJson('/remove-nonexistent');
          res
            ..assertStatus(200)
            ..assertJsonPath('removed', true);
        });
      },
    );
  });
}
