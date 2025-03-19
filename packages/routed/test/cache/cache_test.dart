import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  CacheManager cacheManager = CacheManager()
    ..registerStore('array', {
      'driver': 'array',
      'serialize': false,
    })
    ..registerStore('file', {
      'driver': 'file',
      'path': 'cache',
    });

  group('ContextCache', () {
    engineGroup(
      'Cache operations',
      configItems: {'app.name': 'Test App'},
      options: [
        withCacheManager(cacheManager),
        (engine) {
          // Add a test route that uses caching
          engine.get('/cached-value', (ctx) async {
            // Try to get from cache first
            final value = await ctx.getCache('test-key');
            if (value != null) {
              return ctx.json({'value': value, 'from_cache': true});
            }

            // Set in cache and return
            final newValue = 'test-value';
            await ctx.cache('test-key', newValue, 60);
            return ctx.json({'value': newValue, 'from_cache': false});
          });

          // Add a route for testing increment/decrement
          engine.get('/counter', (ctx) async {
            await ctx.cache('counter', 0, 60);
            await ctx.incrementCache('counter', 5);
            await ctx.decrementCache('counter', 2);
            final value = await ctx.getCache('counter');
            return ctx.json({'value': value});
          });

          // Add a route for testing remember cache
          engine.get('/remember', (ctx) async {
            final value = await ctx.rememberCache(
                'remembered-key', 60, () => 'computed-value');
            return ctx.json({'value': value});
          });
        },
      ],
      define: (engine, client) {
        test('basic cache operations', () async {
          // First request should cache the value
          var response = await client.getJson('/cached-value');
          response
            ..dump()
            ..assertStatus(200)
            ..assertJson((json) {
              json.where('value', 'test-value').where('from_cache', false);
            });

          // Second request should get from cache
          response = await client.getJson('/cached-value');
          response
            ..assertStatus(200)
            ..assertJson((json) {
              json.where('value', 'test-value').where('from_cache', true);
            });
        });

        test('increment and decrement operations', () async {
          final response = await client.getJson('/counter');
          response
            ..assertStatus(200)
            ..assertJson((json) {
              json.where('value', 3);
            });
        });

        test('remember cache operation', () async {
          final response = await client.getJson('/remember');
          response
            ..assertStatus(200)
            ..assertJson((json) {
              json.where('value', 'computed-value');
            });
        });
      },
    );
  });
}
