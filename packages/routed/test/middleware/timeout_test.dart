import 'package:property_testing/property_testing.dart';
import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('timeoutMiddleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        test('returns 504 when handler exceeds allotted time', () async {
          final engine = Engine()
            ..get(
              '/slow',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                return ctx.string('late');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 20)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/slow');
          response
            ..assertStatus(HttpStatus.gatewayTimeout)
            ..assertBodyContains('Gateway Timeout');
        });

        test('allows fast handler to complete within timeout', () async {
          final engine = Engine()
            ..get(
              '/fast',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                return ctx.string('ok');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 100)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/fast');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');
        });

        test('allows synchronous handlers to complete', () async {
          final engine = Engine()
            ..get(
              '/sync',
              (ctx) => ctx.string('instant'),
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 50)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/sync');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('instant');
        });

        test('works with very short timeouts', () async {
          final engine = Engine()
            ..get(
              '/very-slow',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
                return ctx.string('done');
              },
              middlewares: [timeoutMiddleware(const Duration(milliseconds: 5))],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/very-slow');
          response.assertStatus(HttpStatus.gatewayTimeout);
        });

        test('works with generous timeouts', () async {
          final engine = Engine()
            ..get(
              '/reasonable',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
                return ctx.string('completed');
              },
              middlewares: [timeoutMiddleware(const Duration(seconds: 5))],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/reasonable');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('completed');
        });

        test('timeout applies per request independently', () async {
          final engine = Engine()
            ..get(
              '/mixed-1',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 5));
                return ctx.string('fast');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 50)),
              ],
            )
            ..get(
              '/mixed-2',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                return ctx.string('slow');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 50)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);

          final fastResponse = await client.get('/mixed-1');
          fastResponse
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('fast');

          final slowResponse = await client.get('/mixed-2');
          slowResponse.assertStatus(HttpStatus.gatewayTimeout);
        });

        test('different routes can have different timeouts', () async {
          final engine = Engine()
            ..get(
              '/short-timeout',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                return ctx.string('done');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 10)),
              ],
            )
            ..get(
              '/long-timeout',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                return ctx.string('done');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 100)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);

          final shortResponse = await client.get('/short-timeout');
          shortResponse.assertStatus(HttpStatus.gatewayTimeout);

          final longResponse = await client.get('/long-timeout');
          longResponse
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('done');
        });

        test('timeout does not affect response content type', () async {
          final engine = Engine()
            ..get(
              '/json-timeout',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                return ctx.json({'status': 'ok'});
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 20)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/json-timeout');
          response.assertStatus(HttpStatus.gatewayTimeout);
        });

        test('successful requests return correct content', () async {
          final engine = Engine()
            ..get(
              '/data',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                return ctx.json({
                  'data': [1, 2, 3],
                  'count': 3,
                });
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 100)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/data');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertJsonPath('count', 3)
            ..assertJson((json) => json.has('data'));
        });

        test('works with middleware chain', () async {
          var otherMiddlewareExecuted = false;

          Future<Response> testMiddleware(EngineContext ctx, Next next) async {
            otherMiddlewareExecuted = true;
            return next();
          }

          final engine = Engine()
            ..get(
              '/chained',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                return ctx.string('ok');
              },
              middlewares: [
                testMiddleware,
                timeoutMiddleware(const Duration(milliseconds: 100)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/chained');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');

          expect(otherMiddlewareExecuted, isTrue);
        });

        test('timeout triggers even with middleware chain', () async {
          Future<Response> slowMiddleware(EngineContext ctx, Next next) async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return next();
          }

          final engine = Engine()
            ..get(
              '/slow-chain',
              (ctx) => ctx.string('ok'),
              middlewares: [
                slowMiddleware,
                timeoutMiddleware(const Duration(milliseconds: 30)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/slow-chain');
          response.assertStatus(HttpStatus.gatewayTimeout);
        });

        test('multiple sequential requests each get fresh timeout', () async {
          final engine = Engine()
            ..get(
              '/timed',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return ctx.string('ok');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 50)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);

          for (var i = 0; i < 3; i++) {
            final response = await client.get('/timed');
            response
              ..assertStatus(HttpStatus.ok)
              ..assertBodyEquals('ok');
          }
        });

        test('timeout message is descriptive', () async {
          final engine = Engine()
            ..get(
              '/timeout-msg',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                return ctx.string('done');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 10)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/timeout-msg');
          response
            ..assertStatus(HttpStatus.gatewayTimeout)
            ..assertBodyContains('Timeout');
        });

        test('zero timeout fails immediately', () async {
          final engine = Engine()
            ..get('/zero', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              return ctx.string('ok');
            }, middlewares: [timeoutMiddleware(Duration.zero)]);

          final client = _startTimeoutClient(engine, mode);
          final response = await client.get('/zero');
          response.assertStatus(HttpStatus.gatewayTimeout);
        });

        test('handles POST requests with timeout', () async {
          final engine = Engine()
            ..post(
              '/upload',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return ctx.json({'uploaded': true});
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 100)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.post('/upload', {'data': 'test'});
          response
            ..assertStatus(HttpStatus.ok)
            ..assertJsonPath('uploaded', true);
        });

        test('handles PUT requests with timeout', () async {
          final engine = Engine()
            ..put(
              '/update',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                return ctx.string('updated');
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 20)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.put('/update', {'id': 1});
          response.assertStatus(HttpStatus.gatewayTimeout);
        });

        test('handles DELETE requests with timeout', () async {
          final engine = Engine()
            ..delete(
              '/remove',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                return ctx.status(HttpStatus.noContent);
              },
              middlewares: [
                timeoutMiddleware(const Duration(milliseconds: 50)),
              ],
            );

          final client = _startTimeoutClient(engine, mode);
          final response = await client.delete('/remove');
          response.assertStatus(HttpStatus.noContent);
        });

        test('timeouts respond based on latency (property)', () async {
          final runner = PropertyTestRunner<_TimeoutSample>(
            _timeoutSampleGen(),
            (sample) async {
              final engine = Engine()
                ..get(
                  '/prop',
                  (ctx) async {
                    await Future<void>.delayed(
                      Duration(milliseconds: sample.handlerDelayMs),
                    );
                    return ctx.string('ok');
                  },
                  middlewares: [
                    timeoutMiddleware(Duration(milliseconds: sample.timeoutMs)),
                  ],
                );

              final client = TestClient(
                RoutedRequestHandler(engine),
                mode: mode,
              );
              final response = await client.get('/prop');

              const jitterMs = 30;
              if (sample.handlerDelayMs >= sample.timeoutMs + jitterMs) {
                response.assertStatus(HttpStatus.gatewayTimeout);
              } else if (sample.handlerDelayMs <= sample.timeoutMs - jitterMs) {
                response
                  ..assertStatus(HttpStatus.ok)
                  ..assertBodyEquals('ok');
              } else {
                expect(
                  response.statusCode,
                  anyOf(HttpStatus.ok, HttpStatus.gatewayTimeout),
                  reason: 'Timeout window is too narrow to assert determinism.',
                );
              }

              await client.close();
              await engine.close();
            },
            PropertyConfig(numTests: 35, seed: 20250317),
          );

          final result = await runner.run();
          expect(result.success, isTrue, reason: result.report);
        });
      });
    }
  });
}

typedef _TimeoutSample = ({int timeoutMs, int handlerDelayMs});

Generator<_TimeoutSample> _timeoutSampleGen() =>
    Gen.integer(min: 5, max: 120).flatMap(
      (timeoutMs) => Gen.integer(min: 0, max: 200).map(
        (handlerDelayMs) =>
            (timeoutMs: timeoutMs, handlerDelayMs: handlerDelayMs),
      ),
    );

TestClient _startTimeoutClient(Engine engine, TransportMode mode) {
  final client = TestClient(RoutedRequestHandler(engine), mode: mode);
  addTearDown(client.close);
  addTearDown(engine.close);
  return client;
}
