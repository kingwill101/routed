import 'package:routed/routed.dart';
import 'package:routed/middlewares.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('requestTrackerMiddleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        tearDown(() async {
          await client.close();
        });

        test(
          'stores duration and completion metadata under routed keys',
          () async {
            Future<Response> verifier(EngineContext ctx, Next next) async {
              final res = await next();
              final duration = ctx.getContextData<Duration>(
                '_routed_request_duration',
              );
              final completed = ctx.getContextData<DateTime>(
                '_routed_request_completed',
              );
              ctx.response.headers.set(
                'X-Tracker-Has-Duration',
                (duration is Duration).toString(),
              );
              ctx.response.headers.set(
                'X-Tracker-Has-Completed',
                (completed is DateTime).toString(),
              );
              return res;
            }

            final engine = Engine()
              ..get('/tracked', (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 5));
                return ctx.string('ok');
              }, middlewares: [verifier, requestTrackerMiddleware()]);

            client = TestClient(RoutedRequestHandler(engine), mode: mode);
            final response = await client.get('/tracked');
            response
              ..assertStatus(HttpStatus.ok)
              ..assertHeader('X-Tracker-Has-Duration', 'true')
              ..assertHeader('X-Tracker-Has-Completed', 'true');
          },
        );

        test('duration increases with request processing time', () async {
          Duration? capturedDuration;

          Future<Response> capturer(EngineContext ctx, Next next) async {
            final res = await next();
            capturedDuration = ctx.getContextData<Duration>(
              '_routed_request_duration',
            );
            return res;
          }

          final engine = Engine()
            ..get('/slow', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return ctx.string('done');
            }, middlewares: [capturer, requestTrackerMiddleware()]);

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/slow');
          response.assertStatus(HttpStatus.ok);

          expect(capturedDuration, isNotNull);
          expect(capturedDuration!.inMilliseconds, greaterThanOrEqualTo(40));
        });

        test('completion timestamp is after request start', () async {
          DateTime? completedTime;
          DateTime? startTime;

          Future<Response> timeTracker(EngineContext ctx, Next next) async {
            startTime = DateTime.now();
            final res = await next();
            completedTime = ctx.getContextData<DateTime>(
              '_routed_request_completed',
            );
            return res;
          }

          final engine = Engine()
            ..get('/timed', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return ctx.string('ok');
            }, middlewares: [timeTracker, requestTrackerMiddleware()]);

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/timed');
          response.assertStatus(HttpStatus.ok);

          expect(startTime, isNotNull);
          expect(completedTime, isNotNull);
          expect(
            completedTime!.isAfter(startTime!),
            isTrue,
            reason: 'Completion time should be after start time',
          );
        });

        test('tracks multiple sequential requests independently', () async {
          final durations = <Duration>[];

          Future<Response> collector(EngineContext ctx, Next next) async {
            final res = await next();
            final duration = ctx.getContextData<Duration>(
              '_routed_request_duration',
            );
            if (duration != null) {
              durations.add(duration);
            }
            return res;
          }

          final engine = Engine()
            ..get('/req1', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return ctx.string('req1');
            }, middlewares: [collector, requestTrackerMiddleware()])
            ..get('/req2', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return ctx.string('req2');
            }, middlewares: [collector, requestTrackerMiddleware()])
            ..get('/req3', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              return ctx.string('req3');
            }, middlewares: [collector, requestTrackerMiddleware()]);

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          await client.get('/req1');
          await client.get('/req2');
          await client.get('/req3');

          expect(durations.length, equals(3));
          expect(durations[0].inMilliseconds, greaterThanOrEqualTo(5));
          expect(durations[1].inMilliseconds, greaterThanOrEqualTo(15));
          expect(durations[2].inMilliseconds, greaterThanOrEqualTo(3));
        });

        test('works with fast synchronous handlers', () async {
          Duration? fastDuration;

          Future<Response> fastTracker(EngineContext ctx, Next next) async {
            final res = await next();
            fastDuration = ctx.getContextData<Duration>(
              '_routed_request_duration',
            );
            return res;
          }

          final engine = Engine()
            ..get(
              '/fast',
              (ctx) => ctx.string('instant'),
              middlewares: [fastTracker, requestTrackerMiddleware()],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/fast');
          response.assertStatus(HttpStatus.ok);

          expect(fastDuration, isNotNull);
          expect(fastDuration!.inMicroseconds, greaterThanOrEqualTo(0));
        });

        test('data is available to subsequent middleware', () async {
          var durationAvailable = false;
          var completedAvailable = false;

          Future<Response> checker(EngineContext ctx, Next next) async {
            final res = await next();
            durationAvailable =
                ctx.getContextData<Duration>('_routed_request_duration') !=
                null;
            completedAvailable =
                ctx.getContextData<DateTime>('_routed_request_completed') !=
                null;
            return res;
          }

          final engine = Engine()
            ..get(
              '/check',
              (ctx) => ctx.string('ok'),
              middlewares: [requestTrackerMiddleware(), checker],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/check');
          response.assertStatus(HttpStatus.ok);

          expect(durationAvailable, isTrue);
          expect(completedAvailable, isTrue);
        });

        test('continues tracking even if handler throws', () async {
          Duration? errorDuration;

          Future<Response> errorTracker(EngineContext ctx, Next next) async {
            try {
              return await next();
            } catch (e) {
              errorDuration = ctx.getContextData<Duration>(
                '_routed_request_duration',
              );
              rethrow;
            }
          }

          final engine = Engine()
            ..middlewares.add(
              recoveryMiddleware(
                handler: (ctx, error, stack) {
                  ctx.response
                    ..statusCode = HttpStatus.internalServerError
                    ..write('error');
                  ctx.response.close();
                },
              ),
            )
            ..get('/error', (ctx) {
              throw Exception('Test error');
            }, middlewares: [errorTracker, requestTrackerMiddleware()]);

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          await client.get('/error');

          expect(errorDuration, isNotNull);
        });

        test('metadata persists through the entire middleware chain', () async {
          var earlyDuration = false;
          var lateDuration = false;

          Future<Response> earlyCheck(EngineContext ctx, Next next) async {
            final res = await next();
            earlyDuration =
                ctx.getContextData<Duration>('_routed_request_duration') !=
                null;
            return res;
          }

          Future<Response> lateCheck(EngineContext ctx, Next next) async {
            final res = await next();
            lateDuration =
                ctx.getContextData<Duration>('_routed_request_duration') !=
                null;
            return res;
          }

          final engine = Engine()
            ..get(
              '/chain',
              (ctx) => ctx.string('ok'),
              middlewares: [requestTrackerMiddleware(), earlyCheck, lateCheck],
            );

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/chain');
          response.assertStatus(HttpStatus.ok);

          expect(earlyDuration, isTrue);
          expect(lateDuration, isTrue);
        });

        test('can be used for custom logging', () async {
          final logs = <String>[];

          Future<Response> logger(EngineContext ctx, Next next) async {
            final res = await next();
            final duration = ctx.getContextData<Duration>(
              '_routed_request_duration',
            );
            final completed = ctx.getContextData<DateTime>(
              '_routed_request_completed',
            );
            logs.add(
              'Request completed at ${completed?.toIso8601String()} '
              'took ${duration?.inMilliseconds}ms',
            );
            return res;
          }

          final engine = Engine()
            ..get('/logged', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              return ctx.string('ok');
            }, middlewares: [requestTrackerMiddleware(), logger]);

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/logged');
          response.assertStatus(HttpStatus.ok);

          expect(logs.length, equals(1));
          expect(logs.first, contains('Request completed at'));
          expect(logs.first, contains('took'));
          expect(logs.first, contains('ms'));
        });
      });
    }
  });
}
