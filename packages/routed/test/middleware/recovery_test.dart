import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/middlewares.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('recoveryMiddleware', () {
    for (final mode in TransportMode.values) {
      group('with ${mode.name} transport', () {
        late TestClient client;

        tearDown(() async {
          await client.close();
        });

        test(
          'respects custom handler response without overriding body',
          () async {
            final engine = Engine()
              ..middlewares.add(
                recoveryMiddleware(
                  handler: (ctx, error, stack) {
                    ctx.response
                      ..statusCode = HttpStatus.serviceUnavailable
                      ..write('handled');
                    ctx.response.close();
                  },
                ),
              )
              ..get('/boom', (ctx) {
                throw StateError('boom');
              });

            client = TestClient(RoutedRequestHandler(engine), mode: mode);
            final response = await client.get('/boom');
            response
              ..assertStatus(HttpStatus.serviceUnavailable)
              ..assertBodyEquals('handled');
          },
        );

        test('catches and handles exceptions with default handler', () async {
          final engine = Engine()
            ..middlewares.add(recoveryMiddleware())
            ..get('/error', (ctx) {
              throw Exception('Something went wrong');
            });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/error');
          response.assertStatus(HttpStatus.internalServerError);
        });

        test('allows normal requests to proceed', () async {
          final engine = Engine()
            ..middlewares.add(recoveryMiddleware())
            ..get('/ok', (ctx) => ctx.string('success'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/ok');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('success');
        });

        test('catches errors from async handlers', () async {
          final engine = Engine()
            ..middlewares.add(recoveryMiddleware())
            ..get('/async-error', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('async error');
            });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/async-error');
          response.assertStatus(HttpStatus.internalServerError);
        });

        test('custom handler can set specific status codes', () async {
          final engine = Engine()
            ..middlewares.add(
              recoveryMiddleware(
                handler: (ctx, error, stack) {
                  if (error is ArgumentError) {
                    ctx.response.statusCode = HttpStatus.badRequest;
                    ctx.response.write('Bad request');
                  } else {
                    ctx.response.statusCode = HttpStatus.internalServerError;
                    ctx.response.write('Internal error');
                  }
                  ctx.response.close();
                },
              ),
            )
            ..get('/bad', (ctx) {
              throw ArgumentError('Invalid argument');
            })
            ..get('/internal', (ctx) {
              throw StateError('Internal error');
            });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);

          final badResponse = await client.get('/bad');
          badResponse
            ..assertStatus(HttpStatus.badRequest)
            ..assertBodyEquals('Bad request');

          final internalResponse = await client.get('/internal');
          internalResponse
            ..assertStatus(HttpStatus.internalServerError)
            ..assertBodyEquals('Internal error');
        });

        test('custom handler can return JSON error responses', () async {
          final engine = Engine()
            ..middlewares.add(
              recoveryMiddleware(
                handler: (ctx, error, stack) {
                  ctx.response
                    ..statusCode = HttpStatus.internalServerError
                    ..headers.contentType = ContentType.json
                    ..write('{"error": "${error.toString()}"}');
                  ctx.response.close();
                },
              ),
            )
            ..get('/json-error', (ctx) {
              throw Exception('JSON error');
            });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/json-error');
          response
            ..assertStatus(HttpStatus.internalServerError)
            ..assertJsonPath('error', contains('JSON error'));
        });

        test('does not interfere with middleware chain', () async {
          var middlewareExecuted = false;

          Future<Response> testMiddleware(EngineContext ctx, Next next) async {
            middlewareExecuted = true;
            return next();
          }

          final engine = Engine()
            ..middlewares.addAll([recoveryMiddleware(), testMiddleware])
            ..get('/test', (ctx) => ctx.string('ok'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/test');
          response
            ..assertStatus(HttpStatus.ok)
            ..assertBodyEquals('ok');

          expect(middlewareExecuted, isTrue);
        });

        test('catches errors thrown in middleware', () async {
          Future<Response> errorMiddleware(EngineContext ctx, Next next) async {
            throw StateError('Middleware error');
          }

          final engine = Engine()
            ..middlewares.addAll([recoveryMiddleware(), errorMiddleware])
            ..get('/test', (ctx) => ctx.string('ok'));

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/test');
          response.assertStatus(HttpStatus.internalServerError);
        });

        test('handles FormatException appropriately', () async {
          final engine = Engine()
            ..middlewares.add(
              recoveryMiddleware(
                handler: (ctx, error, stack) {
                  if (error is FormatException) {
                    ctx.response.statusCode = HttpStatus.unprocessableEntity;
                    ctx.response.write('Invalid format');
                  } else {
                    ctx.response.statusCode = HttpStatus.internalServerError;
                    ctx.response.write('Error');
                  }
                  ctx.response.close();
                },
              ),
            )
            ..get('/format-error', (ctx) {
              throw const FormatException('Bad format');
            });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          final response = await client.get('/format-error');
          response
            ..assertStatus(HttpStatus.unprocessableEntity)
            ..assertBodyEquals('Invalid format');
        });

        test('stack trace is available to custom handler', () async {
          StackTrace? capturedStack;

          final engine = Engine()
            ..middlewares.add(
              recoveryMiddleware(
                handler: (ctx, error, stack) {
                  capturedStack = stack;
                  ctx.response
                    ..statusCode = HttpStatus.internalServerError
                    ..write('Error handled');
                  ctx.response.close();
                },
              ),
            )
            ..get('/stack-test', (ctx) {
              throw Exception('Test error');
            });

          client = TestClient(RoutedRequestHandler(engine), mode: mode);
          await client.get('/stack-test');

          expect(capturedStack, isNotNull);
          expect(capturedStack.toString(), contains('stack-test'));
        });
      });
    }
  });
}
