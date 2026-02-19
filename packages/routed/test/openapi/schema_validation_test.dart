import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

TestClient useClient(Engine engine) =>
    TestClient(RoutedRequestHandler(engine), mode: TransportMode.inMemory);

void main() {
  group('Schema auto-validation', () {
    group('JSON body validation', () {
      test('passes validation and reaches handler', () async {
        final engine = testEngine();
        engine.post(
          '/users',
          (ctx) async {
            return ctx.json({'status': 'created'});
          },
          schema: RouteSchema.fromRules({
            'name': 'required|string',
            'email': 'required|email',
          }),
        );

        final client = useClient(engine);
        final response = await client.postJson('/users', {
          'name': 'Alice',
          'email': 'alice@example.com',
        });

        response.assertStatus(HttpStatus.ok);
        response.assertJsonContains({'status': 'created'});
        await client.close();
      });

      test('returns 422 when required fields are missing', () async {
        final engine = testEngine();
        engine.post(
          '/users',
          (ctx) async {
            return ctx.json({'status': 'created'});
          },
          schema: RouteSchema.fromRules({
            'name': 'required|string',
            'email': 'required|email',
          }),
        );

        final client = useClient(engine);
        final response = await client.postJson(
          '/users',
          <String, Object?>{},
          headers: <String, List<String>>{
            'Accept': ['application/json'],
          },
        );

        response.assertStatus(HttpStatus.unprocessableEntity);
        await client.close();
      });

      test('returns 422 with field error details', () async {
        final engine = testEngine();
        engine.post(
          '/users',
          (ctx) async {
            return ctx.json({'status': 'created'});
          },
          schema: RouteSchema.fromRules({
            'name': 'required|string',
            'email': 'required|email',
          }),
        );

        final client = useClient(engine);
        // Send only name, missing email
        final response = await client.postJson(
          '/users',
          {'name': 'Alice'},
          headers: <String, List<String>>{
            'Accept': ['application/json'],
          },
        );

        response.assertStatus(HttpStatus.unprocessableEntity);
        // The response body should contain error details for the email field
        // ValidationError.errors is sent directly as the JSON body
        final json = response.json() as Map<String, Object?>;
        expect(json, isA<Map<String, Object?>>());
        expect(json.containsKey('email'), isTrue);
        await client.close();
      });

      test('validates field constraints (min length)', () async {
        final engine = testEngine();
        engine.post(
          '/users',
          (ctx) async {
            return ctx.json({'status': 'created'});
          },
          schema: RouteSchema.fromRules({'name': 'required|string|min:3'}),
        );

        final client = useClient(engine);
        // Name is too short
        final response = await client.postJson('/users', {'name': 'Ab'});

        response.assertStatus(HttpStatus.unprocessableEntity);
        await client.close();
      });

      test('handler is NOT reached when validation fails', () async {
        var handlerCalled = false;
        final engine = testEngine();
        engine.post('/users', (ctx) async {
          handlerCalled = true;
          return ctx.json({'status': 'created'});
        }, schema: RouteSchema.fromRules({'name': 'required'}));

        final client = useClient(engine);
        final response = await client.postJson('/users', <String, Object?>{});

        response.assertStatus(HttpStatus.unprocessableEntity);
        expect(
          handlerCalled,
          isFalse,
          reason: 'Handler should not be called when schema validation fails',
        );
        await client.close();
      });

      test('handler IS reached when validation passes', () async {
        var handlerCalled = false;
        final engine = testEngine();
        engine.post('/users', (ctx) async {
          handlerCalled = true;
          return ctx.json({'status': 'created'});
        }, schema: RouteSchema.fromRules({'name': 'required'}));

        final client = useClient(engine);
        final response = await client.postJson('/users', {'name': 'Alice'});

        response.assertStatus(HttpStatus.ok);
        expect(
          handlerCalled,
          isTrue,
          reason: 'Handler should be called when schema validation passes',
        );
        await client.close();
      });
    });

    group('numeric validation rules', () {
      test('validates numeric type constraint', () async {
        final engine = testEngine();
        engine.post('/items', (ctx) async {
          return ctx.json({'status': 'ok'});
        }, schema: RouteSchema.fromRules({'quantity': 'required|numeric'}));

        final client = useClient(engine);
        final response = await client.postJson('/items', {
          'quantity': 'not-a-number',
        });

        response.assertStatus(HttpStatus.unprocessableEntity);
        await client.close();
      });

      test('passes numeric validation with valid number', () async {
        final engine = testEngine();
        engine.post('/items', (ctx) async {
          return ctx.json({'status': 'ok'});
        }, schema: RouteSchema.fromRules({'quantity': 'required|numeric'}));

        final client = useClient(engine);
        final response = await client.postJson('/items', {'quantity': 42});

        response.assertStatus(HttpStatus.ok);
        await client.close();
      });
    });

    group('routes without schema', () {
      test('no validation when schema is null', () async {
        final engine = testEngine();
        engine.post('/open', (ctx) async {
          return ctx.json({'status': 'ok'});
        });

        final client = useClient(engine);
        // Send empty body — should succeed because no schema validation
        final response = await client.postJson('/open', <String, Object?>{});

        response.assertStatus(HttpStatus.ok);
        await client.close();
      });

      test('no validation when schema has no validationRules', () async {
        final engine = testEngine();
        engine.post(
          '/documented',
          (ctx) async {
            return ctx.json({'status': 'ok'});
          },
          schema: const RouteSchema(summary: 'A documented endpoint'),
        );

        final client = useClient(engine);
        // Send empty body — should succeed because schema has no validation rules
        final response = await client.postJson(
          '/documented',
          <String, Object?>{},
        );

        response.assertStatus(HttpStatus.ok);
        await client.close();
      });
    });

    group('schema with RouteBuilder chaining', () {
      test('validation works with schema() chaining method', () async {
        final engine = testEngine();
        engine
            .post('/items', (ctx) async {
              return ctx.json({'status': 'created'});
            })
            .schema(RouteSchema.fromRules({'title': 'required|string'}));

        final client = useClient(engine);
        // Missing required 'title' field
        final response = await client.postJson('/items', <String, Object?>{});

        response.assertStatus(HttpStatus.unprocessableEntity);
        await client.close();
      });
    });

    group('middleware ordering', () {
      test('custom middleware runs before schema validation', () async {
        final order = <String>[];

        Middleware trackMiddleware(String label) {
          return (ctx, next) {
            order.add(label);
            return next();
          };
        }

        final engine = testEngine();
        engine.post(
          '/tracked',
          (ctx) async {
            order.add('handler');
            return ctx.json({'status': 'ok'});
          },
          middlewares: [trackMiddleware('custom')],
          schema: RouteSchema.fromRules({'name': 'required'}),
        );

        final client = useClient(engine);
        final response = await client.postJson('/tracked', {'name': 'Alice'});

        response.assertStatus(HttpStatus.ok);
        // Custom middleware should run before handler
        expect(order, contains('custom'));
        expect(order, contains('handler'));
        expect(order.indexOf('custom'), lessThan(order.indexOf('handler')));
        await client.close();
      });
    });

    group('multiple validation rules', () {
      test('validates all fields and reports all errors', () async {
        final engine = testEngine();
        engine.post(
          '/register',
          (ctx) async {
            return ctx.json({'status': 'created'});
          },
          schema: RouteSchema.fromRules({
            'username': 'required|string|min:3',
            'email': 'required|email',
            'age': 'required|numeric',
          }),
        );

        final client = useClient(engine);
        // All fields invalid or missing
        final response = await client.postJson(
          '/register',
          <String, Object?>{},
          headers: <String, List<String>>{
            'Accept': ['application/json'],
          },
        );

        response.assertStatus(HttpStatus.unprocessableEntity);
        // ValidationError.errors is sent directly as the JSON body
        final json = response.json() as Map<String, Object?>;
        // All three fields should have errors
        expect(json.containsKey('username'), isTrue);
        expect(json.containsKey('email'), isTrue);
        expect(json.containsKey('age'), isTrue);
        await client.close();
      });
    });
  });
}
