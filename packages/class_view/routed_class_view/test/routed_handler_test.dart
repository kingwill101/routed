import 'package:routed/routed.dart' as routed;
import 'package:routed_class_view/routed_class_view.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

// Test views for integration testing
class SimpleView extends View {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  Future<void> get() async {
    await sendJson({'message': 'Hello from SimpleView', 'method': 'GET'});
  }

  @override
  Future<void> post() async {
    final body = await getJsonBody();
    await sendJson({
      'message': 'Posted successfully',
      'method': 'POST',
      'body': body,
    });
  }
}

class ParameterizedView extends View {
  @override
  Future<void> get() async {
    final id = await getParam('id');
    final search = await getParam('search');
    final framework = await getParam('framework');
    await sendJson({
      'id': id,
      'search': search,
      'framework': framework,
      'allParams': await getParams(),
    });
  }
}

class RedirectView extends View {
  @override
  Future<void> get() async {
    await redirect('/redirected');
  }
}

class StatusCodeView extends View {
  @override
  Future<void> get() async {
    await sendJson({'status': 'created'}, statusCode: 201);
  }
}

void main() {
  group('RoutedViewHandler Integration Tests', () {
    late routed.Engine app;
    late TestClient client;

    setUp(() async {
      app = routed.Engine();

      // Register different types of views to test handler functionality
      app.getView('/simple', () => SimpleView());
      app.postView('/simple', () => SimpleView());
      app.getView('/params/{id}', () => ParameterizedView());
      app.getView('/redirect', () => RedirectView());
      app.getView('/status', () => StatusCodeView());

      // Create test client
      final handler = RoutedRequestHandler(app);
      client = TestClient.inMemory(handler);
    });

    tearDown(() async {
      await client.close();
    });

    group('Handler Integration', () {
      test('should handle GET requests correctly', () async {
        final response = await client.get('/simple');

        response.assertStatus(200).assertJson((json) {
          json.where('message', 'Hello from SimpleView').where('method', 'GET');
        });
      });

      test('should handle POST requests with JSON body', () async {
        final requestData = {'key': 'value', 'number': 42};
        final response = await client.postJson('/simple', requestData);

        response.assertStatus(200).assertJson((json) {
          json
              .where('message', 'Posted successfully')
              .where('method', 'POST')
              .has('body')
              .where('body.key', 'value')
              .where('body.number', 42);
        });
      });

      test('should extract route parameters', () async {
        final response = await client.get('/params/user123?search=test');

        response.assertStatus(200).assertJson((json) {
          json.where('id', 'user123').where('search', 'test').has('allParams');
        });
      });

      test('should handle redirects', () async {
        final response = await client.get('/redirect');

        // Check for redirect status code
        expect(response.statusCode, equals(302));
      });

      test('should handle custom status codes', () async {
        final response = await client.get('/status');

        response.assertStatus(201).assertJson((json) {
          json.where('status', 'created');
        });
      });
    });

    group('Router Extensions', () {
      test('getView extension should work correctly', () async {
        final response = await client.get('/simple');
        response.assertStatus(200);
      });

      test('postView extension should work correctly', () async {
        final response = await client.postJson('/simple', {});
        response.assertStatus(200);
      });
    });

    group('Real HTTP Flow', () {
      test('should demonstrate full request/response cycle', () async {
        // Test the complete flow: request -> handler -> adapter -> view -> response
        final response = await client.get(
          '/params/integration-test?framework=routed',
        );

        response.assertStatus(200).assertJson((json) {
          json
              .where('id', 'integration-test')
              .where('framework', 'routed')
              .has('allParams');
        });

        print('✅ RoutedViewHandler integration test passed!');
        print('✅ Router extensions working correctly');
        print('✅ Full HTTP request/response cycle functional');
      });
    });
  });
}
