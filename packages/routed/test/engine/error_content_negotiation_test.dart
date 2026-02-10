import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/middlewares.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('Error content negotiation', () {
    group('_handleGlobalError', () {
      late Engine engine;
      late TestClient client;

      setUp(() {
        engine = testEngine();
        engine.get('/validation-error', (ctx) {
          throw ValidationError({
            'name': ['required'],
          });
        });
        engine.get('/not-found-error', (ctx) {
          throw NotFoundError();
        });
        engine.get('/unauthorized-error', (ctx) {
          throw UnauthorizedError(message: 'Unauthorized.');
        });
        engine.get('/internal-error', (ctx) {
          throw StateError('unexpected');
        });
        engine.get('/engine-error', (ctx) {
          throw EngineError(message: 'Something broke', code: 503);
        });
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() async {
        await client.close();
      });

      group('JSON client (Accept: application/json)', () {
        final jsonHeaders = {
          'Accept': ['application/json'],
        };

        test('ValidationError returns JSON', () async {
          final response = await client.get(
            '/validation-error',
            headers: jsonHeaders,
          );
          response.assertStatus(HttpStatus.unprocessableEntity);
          final body = await response.json() as Map<String, dynamic>;
          expect(body['name'], contains('required'));
        });

        test('NotFoundError returns JSON', () async {
          final response = await client.get(
            '/not-found-error',
            headers: jsonHeaders,
          );
          response.assertStatus(HttpStatus.notFound);
          final body = await response.json() as Map<String, dynamic>;
          expect(body['message'], 'Not found.');
          expect(body['code'], 404);
        });

        test('EngineError returns JSON with toJson()', () async {
          final response = await client.get(
            '/engine-error',
            headers: jsonHeaders,
          );
          response.assertStatus(503);
          final body = await response.json() as Map<String, dynamic>;
          expect(body['message'], 'Something broke');
          expect(body['code'], 503);
        });

        test('unexpected error returns JSON', () async {
          final response = await client.get(
            '/internal-error',
            headers: jsonHeaders,
          );
          response.assertStatus(HttpStatus.internalServerError);
          final body = await response.json() as Map<String, dynamic>;
          expect(body['error'], isNotEmpty);
          expect(body['status'], 500);
        });
      });

      group('HTML client (Accept: text/html)', () {
        final htmlHeaders = {
          'Accept': ['text/html, application/xhtml+xml'],
        };

        test('NotFoundError returns HTML', () async {
          final response = await client.get(
            '/not-found-error',
            headers: htmlHeaders,
          );
          response.assertStatus(HttpStatus.notFound);
          expect(response.body, contains('<!DOCTYPE html>'));
          expect(response.body, contains('404'));
        });

        test('ValidationError returns HTML', () async {
          final response = await client.get(
            '/validation-error',
            headers: htmlHeaders,
          );
          response.assertStatus(HttpStatus.unprocessableEntity);
          expect(response.body, contains('<!DOCTYPE html>'));
          expect(response.body, contains('422'));
        });

        test('unexpected error returns HTML', () async {
          final response = await client.get(
            '/internal-error',
            headers: htmlHeaders,
          );
          response.assertStatus(HttpStatus.internalServerError);
          expect(response.body, contains('<!DOCTYPE html>'));
          expect(response.body, contains('500'));
        });
      });

      group('plain client (no Accept header)', () {
        test('NotFoundError returns plain text', () async {
          final response = await client.get('/not-found-error');
          response.assertStatus(HttpStatus.notFound);
          // With no Accept header, ContentNegotiator falls back to first
          // supported type, which is JSON (since errorResponse checks
          // wantsJson first). With no Accept at all and no XHR, wantsJson
          // is false and acceptsHtml is false, so it falls to plain text.
          expect(response.body, isNotEmpty);
        });
      });
    });

    group('404 not found (no matching route)', () {
      late Engine engine;
      late TestClient client;

      setUp(() {
        engine = testEngine();
        engine.get('/exists', (ctx) => ctx.string('ok'));
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() async {
        await client.close();
      });

      test('returns JSON for JSON clients', () async {
        final response = await client.get(
          '/nonexistent',
          headers: {
            'Accept': ['application/json'],
          },
        );
        response.assertStatus(HttpStatus.notFound);
        final body = await response.json() as Map<String, dynamic>;
        expect(body['error'], 'Not Found');
        expect(body['status'], 404);
      });

      test('returns HTML for browser clients', () async {
        final response = await client.get(
          '/nonexistent',
          headers: {
            'Accept': ['text/html'],
          },
        );
        response.assertStatus(HttpStatus.notFound);
        expect(response.body, contains('<!DOCTYPE html>'));
        expect(response.body, contains('404'));
      });

      test('returns plain text with no Accept', () async {
        final response = await client.get('/nonexistent');
        response.assertStatus(HttpStatus.notFound);
        expect(response.body, contains('Not Found'));
      });
    });

    group('XHR detection', () {
      late Engine engine;
      late TestClient client;

      setUp(() {
        engine = testEngine();
        engine.get('/error', (ctx) {
          throw NotFoundError();
        });
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() async {
        await client.close();
      });

      test('X-Requested-With: XMLHttpRequest triggers JSON', () async {
        final response = await client.get(
          '/error',
          headers: {
            'X-Requested-With': ['XMLHttpRequest'],
          },
        );
        response.assertStatus(HttpStatus.notFound);
        final body = await response.json() as Map<String, dynamic>;
        expect(body['message'], 'Not found.');
        expect(body['code'], 404);
      });
    });

    group('recoveryMiddleware content negotiation', () {
      late TestClient client;

      tearDown(() async {
        await client.close();
      });

      test('returns JSON for JSON clients', () async {
        final engine = testEngine()
          ..middlewares.add(recoveryMiddleware())
          ..get('/boom', (ctx) {
            throw Exception('boom');
          });

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.get(
          '/boom',
          headers: {
            'Accept': ['application/json'],
          },
        );
        response.assertStatus(HttpStatus.internalServerError);
        final body = await response.json() as Map<String, dynamic>;
        expect(body['error'], isNotNull);
      });

      test('returns HTML for browser clients', () async {
        final engine = testEngine()
          ..middlewares.add(recoveryMiddleware())
          ..get('/boom', (ctx) {
            throw Exception('boom');
          });

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.get(
          '/boom',
          headers: {
            'Accept': ['text/html'],
          },
        );
        response.assertStatus(HttpStatus.internalServerError);
        expect(response.body, contains('<!DOCTYPE html>'));
        expect(response.body, contains('500'));
      });
    });

    group('wantsJson / acceptsHtml / accepts', () {
      late Engine engine;
      late TestClient client;

      setUp(() {
        engine = testEngine();
        // Routes that expose the negotiation helpers for testing
        engine.get('/check', (ctx) {
          return ctx.json({
            'wantsJson': ctx.wantsJson,
            'acceptsHtml': ctx.acceptsHtml,
            'acceptsXml': ctx.accepts('application/xml'),
          });
        });
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() async {
        await client.close();
      });

      test('wantsJson is true for application/json Accept', () async {
        final response = await client.get(
          '/check',
          headers: {
            'Accept': ['application/json'],
          },
        );
        final body = await response.json() as Map<String, dynamic>;
        expect(body['wantsJson'], isTrue);
        expect(body['acceptsHtml'], isFalse);
      });

      test('wantsJson is true for +json suffix', () async {
        final response = await client.get(
          '/check',
          headers: {
            'Accept': ['application/vnd.api+json'],
          },
        );
        final body = await response.json() as Map<String, dynamic>;
        expect(body['wantsJson'], isTrue);
      });

      test('acceptsHtml is true for text/html Accept', () async {
        final response = await client.get(
          '/check',
          headers: {
            'Accept': ['text/html, application/json'],
          },
        );
        final body = await response.json() as Map<String, dynamic>;
        expect(body['acceptsHtml'], isTrue);
        expect(body['wantsJson'], isTrue);
      });

      test('accepts detects arbitrary mime types', () async {
        final response = await client.get(
          '/check',
          headers: {
            'Accept': ['application/xml'],
          },
        );
        final body = await response.json() as Map<String, dynamic>;
        expect(body['acceptsXml'], isTrue);
        expect(body['wantsJson'], isFalse);
      });

      test('wantsJson is true for XHR requests', () async {
        final response = await client.get(
          '/check',
          headers: {
            'X-Requested-With': ['XMLHttpRequest'],
          },
        );
        final body = await response.json() as Map<String, dynamic>;
        expect(body['wantsJson'], isTrue);
      });

      test('all false with no Accept header', () async {
        final response = await client.get('/check');
        final body = await response.json() as Map<String, dynamic>;
        expect(body['wantsJson'], isFalse);
        expect(body['acceptsHtml'], isFalse);
        expect(body['acceptsXml'], isFalse);
      });
    });
  });
}
