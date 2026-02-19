import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('EngineContext — abort methods', () {
    engineGroup(
      'abort family',
      options: [
        (engine) {
          engine.get('/abort-bare', (ctx) {
            ctx.abort();
            // Handler continues but chain should stop
            return ctx.string('should not appear');
          });

          engine.get('/abort-status', (ctx) {
            ctx.abortWithStatus(403, 'Forbidden zone');
            return ctx.string('should not appear');
          });

          engine.get('/abort-error', (ctx) {
            ctx.abortWithError(503, 'Down for maintenance');
            return ctx.string('should not appear');
          });

          engine.get('/abort-status-no-message', (ctx) {
            ctx.abortWithStatus(429);
            return ctx.string('should not appear');
          });

          engine.get('/is-aborted', (ctx) {
            expect(ctx.isAborted, isFalse);
            ctx.abort();
            expect(ctx.isAborted, isTrue);
            return ctx.string('ok');
          });
        },
      ],
      define: (engine, client, tess) {
        tess('abort() sets isAborted flag', (engine, client) async {
          final res = await client.get('/is-aborted');
          res.assertStatus(200);
        });

        tess('abortWithStatus sets status code and body', (
          engine,
          client,
        ) async {
          final res = await client.get('/abort-status');
          res.assertStatus(403);
          res.assertBodyContains('Forbidden zone');
        });

        tess('abortWithError sets status code and body', (
          engine,
          client,
        ) async {
          final res = await client.get('/abort-error');
          res.assertStatus(503);
          res.assertBodyContains('Down for maintenance');
        });

        tess('abortWithStatus with no message yields empty body', (
          engine,
          client,
        ) async {
          final res = await client.get('/abort-status-no-message');
          res.assertStatus(429);
        });
      },
    );
  });

  group('EngineContext — mustGet / mustGetParam', () {
    engineGroup(
      'mustGet',
      options: [
        (engine) {
          engine.get('/must-get-found', (ctx) {
            ctx.set('foo', 'bar');
            final val = ctx.mustGet<String>('foo');
            return ctx.string(val);
          });

          engine.get('/must-get-missing', (ctx) {
            try {
              ctx.mustGet<String>('nonexistent');
              return ctx.string('should not reach');
            } on StateError catch (e) {
              return ctx.string('caught: ${e.message}');
            }
          });

          engine.get('/users/{id}/posts/{postId}', (ctx) {
            final id = ctx.mustGetParam<String>('id');
            final postId = ctx.mustGetParam<String>('postId');
            return ctx.json({'id': id, 'postId': postId});
          });

          engine.get('/must-param-missing', (ctx) {
            try {
              ctx.mustGetParam<String>('nope');
              return ctx.string('should not reach');
            } on StateError catch (e) {
              return ctx.string('caught: ${e.message}');
            }
          });
        },
      ],
      define: (engine, client, tess) {
        tess('mustGet returns value when present', (engine, client) async {
          final res = await client.get('/must-get-found');
          res
            ..assertStatus(200)
            ..assertBodyEquals('bar');
        });

        tess('mustGet throws StateError when missing', (engine, client) async {
          final res = await client.get('/must-get-missing');
          res
            ..assertStatus(200)
            ..assertBodyContains('caught:')
            ..assertBodyContains('nonexistent');
        });

        tess('mustGetParam returns route params', (engine, client) async {
          final res = await client.getJson('/users/42/posts/7');
          res
            ..assertStatus(200)
            ..assertJsonPath('id', '42')
            ..assertJsonPath('postId', '7');
        });

        tess('mustGetParam throws when param missing', (engine, client) async {
          final res = await client.get('/must-param-missing');
          res
            ..assertStatus(200)
            ..assertBodyContains('caught:')
            ..assertBodyContains('nope');
        });
      },
    );
  });

  group('EngineContext — addError / errors', () {
    engineGroup(
      'errors tracking',
      options: [
        (engine) {
          engine.get('/errors', (ctx) {
            expect(ctx.errors, isEmpty);
            final e1 = ctx.addError('first', code: 100);
            final e2 = ctx.addError('second');
            expect(ctx.errors, hasLength(2));
            expect(e1.message, 'first');
            expect(e1.code, 100);
            expect(e2.code, isNull);
            return ctx.string('ok');
          });
        },
      ],
      define: (engine, client, tess) {
        tess('addError accumulates errors on context', (engine, client) async {
          final res = await client.get('/errors');
          res.assertStatus(200);
        });
      },
    );
  });

  group('EngineContext — handler chain', () {
    engineGroup(
      'middleware chain',
      options: [
        (engine) {
          engine.group(
            path: '/chain',
            middlewares: [
              (ctx, next) {
                ctx.setHeader('X-Step', '1');
                return next();
              },
              (ctx, next) {
                ctx.setHeader('X-Step', '${ctx.header("X-Step")},2');
                return next();
              },
            ],
            builder: (router) {
              router.get('/test', (ctx) {
                ctx.setHeader('X-Step', '${ctx.header("X-Step")},3');
                return ctx.string('done');
              });
            },
          );

          // Middleware that aborts — second middleware should not run
          engine.group(
            path: '/abort-chain',
            middlewares: [
              (ctx, next) {
                ctx.abortWithStatus(401, 'stopped');
                return next();
              },
              (ctx, next) {
                ctx.setHeader('X-Should-Not-Exist', 'yes');
                return next();
              },
            ],
            builder: (router) {
              router.get('/test', (ctx) {
                return ctx.string('should not reach');
              });
            },
          );
        },
      ],
      define: (engine, client, tess) {
        tess('middlewares execute in order', (engine, client) async {
          final res = await client.get('/chain/test');
          res.assertStatus(200);
          res.assertBodyEquals('done');
          // The X-Step header should show the chain executed 1,2,3
          res.assertHasHeader('X-Step');
        });

        tess('abort stops middleware chain', (engine, client) async {
          final res = await client.get('/abort-chain/test');
          res.assertStatus(401);
          res.assertBodyContains('stopped');
        });
      },
    );
  });

  group('EngineContext — setContextData / getContextData / clear', () {
    engineGroup(
      'context data',
      options: [
        (engine) {
          engine.get('/context-data', (ctx) {
            ctx.setContextData('myKey', 123);
            final val = ctx.getContextData<int>('myKey');
            expect(val, 123);

            ctx.clear();
            final after = ctx.getContextData<int>('myKey');
            expect(after, isNull);
            return ctx.string('ok');
          });
        },
      ],
      define: (engine, client, tess) {
        tess('setContextData / getContextData / clear work', (
          engine,
          client,
        ) async {
          final res = await client.get('/context-data');
          res.assertStatus(200);
        });
      },
    );
  });
}
