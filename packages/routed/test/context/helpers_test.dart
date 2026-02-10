import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('EngineContextHelpers — config()', () {
    engineGroup(
      'config helper',
      configItems: {'app.name': 'TestApp', 'app.debug': true},
      options: [
        (engine) {
          engine.get('/config-present', (ctx) {
            final name = ctx.config<String>('app.name');
            return ctx.string(name);
          });

          engine.get('/config-default', (ctx) {
            final val = ctx.config<String>('nonexistent', 'fallback');
            return ctx.string(val);
          });

          engine.get('/config-bool', (ctx) {
            final debug = ctx.config<bool>('app.debug', false);
            return ctx.json({'debug': debug});
          });
        },
      ],
      define: (engine, client, tess) {
        tess('config() returns existing config value', (engine, client) async {
          final res = await client.get('/config-present');
          res
            ..assertStatus(200)
            ..assertBodyEquals('TestApp');
        });

        tess('config() returns default when key missing', (
          engine,
          client,
        ) async {
          final res = await client.get('/config-default');
          res
            ..assertStatus(200)
            ..assertBodyEquals('fallback');
        });

        tess('config() returns typed value', (engine, client) async {
          final res = await client.getJson('/config-bool');
          res
            ..assertStatus(200)
            ..assertJsonPath('debug', true);
        });
      },
    );
  });

  group('EngineContextHelpers — route()', () {
    engineGroup(
      'route helper',
      options: [
        (engine) {
          engine.get('/users', (ctx) => ctx.string('list')).name('users.index');
          engine
              .get('/users/{id}', (ctx) => ctx.string('show'))
              .name('users.show');
          engine
              .get('/users/{id}/posts/{postId}', (ctx) => ctx.string('post'))
              .name('users.post');

          engine.get('/generate-route', (ctx) {
            final url = ctx.route('users.index');
            return ctx.string(url);
          });

          engine.get('/generate-route-params', (ctx) {
            final url = ctx.route('users.show', {'id': '42'});
            return ctx.string(url);
          });

          engine.get('/generate-route-multi-params', (ctx) {
            final url = ctx.route('users.post', {'id': '5', 'postId': '10'});
            return ctx.string(url);
          });

          engine.get('/generate-route-missing', (ctx) {
            try {
              ctx.route('nonexistent.route');
              return ctx.string('should not reach');
            } catch (e) {
              return ctx.string('error: $e');
            }
          });
        },
      ],
      define: (engine, client, tess) {
        tess('route() generates URL for simple route', (engine, client) async {
          final res = await client.get('/generate-route');
          res
            ..assertStatus(200)
            ..assertBodyEquals('/users');
        });

        tess('route() generates URL with single param', (engine, client) async {
          final res = await client.get('/generate-route-params');
          res
            ..assertStatus(200)
            ..assertBodyEquals('/users/42');
        });

        tess('route() generates URL with multiple params', (
          engine,
          client,
        ) async {
          final res = await client.get('/generate-route-multi-params');
          res
            ..assertStatus(200)
            ..assertBodyEquals('/users/5/posts/10');
        });

        tess('route() throws for nonexistent route name', (
          engine,
          client,
        ) async {
          final res = await client.get('/generate-route-missing');
          res
            ..assertStatus(200)
            ..assertBodyContains('error:');
        });
      },
    );
  });
}
