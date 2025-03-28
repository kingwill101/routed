import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('API Chaos Testing', () {
    late Engine engine;
    late TestClient client;

    setUp(() {
      engine = Engine();
      client = TestClient.inMemory(RoutedRequestHandler(engine));

      // // Using type constraints in route definition
      // engine.get('/api/users/{id:uuid}', (ctx) async {
      //   ctx.json({'id': ctx.param("id")});
      // });

      // engine.post('/api/users', (ctx) async {
      //   try {
      //     await ctx.validate({
      //       'name': 'required|string|alpha_dash|max_length:50|not_regex:/[;%]/',
      //       'email': 'required|email|ascii|max_length:255'
      //     }, bail: true);

      //     final data = {};
      //     await ctx.bindJSON(data);
      //     ctx.json(data);
      //   } catch (e) {
      //     ctx.string('Invalid input', statusCode: 422);
      //   }
      // });

      // // Using string type constraint with regex pattern
      // engine.get('/api/search/{q:string}', (ctx) async {
      //   final query = ctx.param("q");
      //   ctx.json({'query': query});
      // }, constraints: {
      //   'q': r'^[a-zA-Z0-9\s]{1,100}'
      // });

      // engine.post('/api/data/{type}', (ctx) async {
      //   try {
      //     await ctx.validate({
      //       'type': 'required|alpha|max_length:20|not_regex:/[;%]/',
      //       'content': 'required|string|max_length:100|json'
      //     }, bail: true);

      //     final type = ctx.param("type");
      //     final data = {};
      //     await ctx.bindJSON(data);
      //     ctx.json({'type': type, 'data': data});
      //   } catch (e) {
      //     ctx.string('Invalid input', statusCode: 422);
      //   }
      // });

      // Basic routes without validation
      engine.get('/api/users/{id}', (ctx) async {
        ctx.json({'id': ctx.param("id")});
      });

      engine.post('/api/users', (ctx) async {
        final data = {};
        ctx.bindJSON(data);
        ctx.json(data);
      });

      engine.get('/api/search', (ctx) async {
        final query = ctx.query("q");
        ctx.json({'query': query});
      });

      engine.post('/api/data/{type}', (ctx) async {
        final type = ctx.param("type");
        final data = {};
        ctx.bindJSON(data);
        ctx.json({'type': type, 'data': data});
      });
    });

    test('GET /api/users/{id} handles chaotic path params', () async {
      final runner = PropertyTestRunner(
        Chaos.string(maxLength: 200),
        (input) async {
          final response = await client.get('/api/users/$input');
          expect(response.statusCode, anyOf([200, 400, 401, 403, 404, 422]));
          expect(response.statusCode, isNot(500));
        },
        PropertyConfig(numTests: 500),
      );

      final result = await runner.run();

      if (!result.success) {
        print("Failing input: ${result.failingInput}");

        print("Number of shrinks ${result.numShrinks}");
        print("Original failing input: ${result.originalFailingInput}");
        print("Error: ${result.error}");
        print("Stack trace: ${result.stackTrace}");
      }
      expect(result.success, isTrue);
    });

    test('POST /api/users handles chaotic JSON body', () async {
      final chaosGen = Chaos.string(maxLength: 200);
      final jsonGen = chaosGen.flatMap((input) =>
          chaosGen.map((input2) => {'name': input, 'email': input2}));

      final runner = PropertyTestRunner(
        jsonGen,
        (json) async {
          final response = await client.postJson('/api/users', json);
          expect(response.statusCode, anyOf([200, 400, 401, 403, 404, 422]));
          expect(response.statusCode, isNot(500));
        },
        PropertyConfig(numTests: 500),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('GET /api/search handles chaotic query params', () async {
      final runner = PropertyTestRunner(
        Chaos.string(maxLength: 200),
        (input) async {
          final response = await client.get('/api/search?q=$input');
          expect(
              response.statusCode, anyOf([200, 400, 401, 403, 404, 413, 422]));
          expect(response.statusCode, isNot(500));
        },
        PropertyConfig(numTests: 500),
      );

      final result = await runner.run();

      if (!result.success) {
        print("Failing input: ${result.failingInput}");

        print("Number of shrinks ${result.numShrinks}");
        print("Original failing input: ${result.originalFailingInput}");
        print("Error: ${result.error}");
        print("Stack trace: ${result.stackTrace}");
      }
      expect(result.success, isTrue);
    });

    test('POST /api/data/{type} handles chaotic path params and body',
        () async {
      final chaosGen = Chaos.string(maxLength: 200);
      final runner = PropertyTestRunner(
        chaosGen,
        (input) async {
          final response =
              await client.postJson('/api/data/$input', {'content': input});
          expect(response.statusCode, anyOf([200, 400, 401, 403, 404, 422]));
          expect(response.statusCode, isNot(500));
        },
        PropertyConfig(numTests: 1),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });
  });
}
