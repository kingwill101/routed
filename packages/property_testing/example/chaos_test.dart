import 'package:property_testing/src/generators.dart';
import 'package:property_testing/src/property_test.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:routed/routed.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('API Chaos Testing', () {
    late Engine engine;

    setUp(() {
      engine = Engine();

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
      final tester = ForAllTester(ChaoticString.chaotic(maxLength: 200),
          config: ExploreConfig(numRuns: 500));

      await tester.check((input) async {
        final client = TestClient.inMemory(RoutedRequestHandler(engine));
        final response = await client.get('/api/users/$input');
        expect(response.statusCode, anyOf([400, 401, 403, 404, 422]));
        expect(response.statusCode, isNot(500));
      });
    });

    test('POST /api/users handles chaotic JSON body', () async {
      final tester = ForAllTester(ChaoticString.chaotic(maxLength: 200),
          config: ExploreConfig(numRuns: 500));

      await tester.check((input) async {
        final client = TestClient.inMemory(RoutedRequestHandler(engine));
        final response = await client
            .postJson('/api/users', {'name': input, 'email': input});
        expect(response.statusCode, anyOf([400, 401, 403, 404, 422]));
        expect(response.statusCode, isNot(500));
      });
    });

    test('GET /api/search handles chaotic query params', () async {
      final tester = ForAllTester(ChaoticString.chaotic(maxLength: 200),
          config: ExploreConfig(numRuns: 500));

      await tester.check((input) async {
        final client = TestClient.inMemory(RoutedRequestHandler(engine));
        final response = await client.get('/api/search?q=$input');
        expect(response.statusCode, anyOf([400, 401, 403, 404, 422]));
        expect(response.statusCode, isNot(500));
      });
    });

    test('POST /api/data/{type} handles chaotic path params and body',
        () async {
      final tester = ForAllTester(ChaoticString.chaotic(maxLength: 200),
          config: ExploreConfig(numRuns: 500));

      await tester.check((input) async {
        final client = TestClient.inMemory(RoutedRequestHandler(engine));
        final response =
            await client.postJson('/api/data/$input', {'content': input});
        expect(response.statusCode, anyOf([400, 401, 403, 404, 422]));
        expect(response.statusCode, isNot(500));
      });
    });
  });
}
