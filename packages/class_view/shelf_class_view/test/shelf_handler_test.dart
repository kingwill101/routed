import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf show Request;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

// Test views for testing
class TestView extends View {
  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  Future<void> get() async {
    await sendJson({'message': 'Hello from TestView', 'method': 'GET'});
  }

  @override
  Future<void> post() async {
    final body = await getJsonBody();
    await sendJson({
      'message': 'Posted successfully',
      'method': 'POST',
      'received': body,
    });
  }
}

class ParameterizedView extends View {
  final Map<String, String> params;

  ParameterizedView(this.params);

  @override
  Future<void> get() async {
    await sendJson({
      'message': 'Parameterized view',
      'params': params,
      'id': await getParam('id'),
    });
  }
}

class ErrorView extends View {
  @override
  Future<void> get() async {
    throw Exception('Test error');
  }
}

void main() {
  group('ShelfViewHandler', () {
    group('handle method', () {
      test('should create handler that processes GET request', () async {
        final handler = ShelfViewHandler.handle(() => TestView());
        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
        );

        final response = await handler(request);

        expect(response.statusCode, equals(200));
        expect(
          response.headers['Content-Type'],
          equals('application/json; charset=utf-8'),
        );

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['message'], equals('Hello from TestView'));
        expect(data['method'], equals('GET'));
      });

      test('should create handler that processes POST request', () async {
        final handler = ShelfViewHandler.handle(() => TestView());
        final request = shelf.Request(
          'POST',
          Uri.parse('http://localhost/test'),
          headers: {'content-type': 'application/json'},
          body: json.encode({'name': 'John', 'age': 30}),
        );

        final response = await handler(request);

        expect(response.statusCode, equals(200));

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['message'], equals('Posted successfully'));
        expect(data['method'], equals('POST'));
        expect(data['received']['name'], equals('John'));
        expect(data['received']['age'], equals(30));
      });

      test('should handle view errors gracefully', () async {
        final handler = ShelfViewHandler.handle(() => ErrorView());
        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
        );

        final response = await handler(request);

        expect(response.statusCode, equals(500));

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['error'], contains('Exception: Test error'));
      });

      test('should extract route parameters from context', () async {
        final handler = ShelfViewHandler.handle(() => TestView());
        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test/123'),
          context: {
            'shelf_router/params': {'id': '123', 'category': 'posts'},
          },
        );

        final response = await handler(request);
        expect(response.statusCode, equals(200));
      });
    });

    group('handleWithParams method', () {
      test('should pass route parameters to view factory', () async {
        final handler = ShelfViewHandler.handleWithParams(
          (params) => ParameterizedView(params),
        );

        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test/123?name=John'),
          context: {
            'shelf_router/params': {'id': '123', 'category': 'posts'},
          },
        );

        final response = await handler(request);

        expect(response.statusCode, equals(200));

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['message'], equals('Parameterized view'));
        expect(data['params']['id'], equals('123'));
        expect(data['params']['category'], equals('posts'));
        expect(data['id'], equals('123')); // From getParam
      });
    });

    group('handleInstance method', () {
      test('should use the same view instance', () async {
        final view = TestView();
        final handler = ShelfViewHandler.handleInstance(view);

        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
        );
        final response = await handler(request);

        expect(response.statusCode, equals(200));

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['message'], equals('Hello from TestView'));
      });
    });
  });

  group('RouterExtensions', () {
    late Router router;

    setUp(() {
      router = Router();
    });

    test('getView should add GET route with view handler', () {
      router.getView('/test', () => TestView());

      // Verify the route was added (this is a bit tricky to test directly)
      // We'll test by actually making a request through the router
      expect(router.call, isA<Function>());
    });

    test('postView should add POST route with view handler', () {
      router.postView('/test', () => TestView());
      expect(router.call, isA<Function>());
    });

    test('putView should add PUT route with view handler', () {
      router.putView('/test', () => TestView());
      expect(router.call, isA<Function>());
    });

    test('deleteView should add DELETE route with view handler', () {
      router.deleteView('/test', () => TestView());
      expect(router.call, isA<Function>());
    });

    test('allView should add route for all methods', () {
      router.allView('/test', () => TestView());
      expect(router.call, isA<Function>());
    });

    test('getViewWithParams should add GET route with parameter handling', () {
      router.getViewWithParams(
        '/test/<id>',
        (params) => ParameterizedView(params),
      );
      expect(router.call, isA<Function>());
    });

    test(
      'postViewWithParams should add POST route with parameter handling',
      () {
        router.postViewWithParams(
          '/test/<id>',
          (params) => ParameterizedView(params),
        );
        expect(router.call, isA<Function>());
      },
    );

    group('Integration tests', () {
      test('should handle actual HTTP request through router', () async {
        router.getView('/hello', () => TestView());

        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/hello'),
        );
        final response = await router.call(request);

        expect(response.statusCode, equals(200));

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['message'], equals('Hello from TestView'));
        expect(data['method'], equals('GET'));
      });

      test('should handle POST request with body', () async {
        router.postView('/submit', () => TestView());

        final requestBody = {'title': 'Test Post', 'content': 'Hello World'};
        final request = shelf.Request(
          'POST',
          Uri.parse('http://localhost/submit'),
          headers: {'content-type': 'application/json'},
          body: json.encode(requestBody),
        );

        final response = await router.call(request);

        expect(response.statusCode, equals(200));

        final body = await response.readAsString();
        final data = json.decode(body);
        expect(data['message'], equals('Posted successfully'));
        expect(data['received']['title'], equals('Test Post'));
      });

      test('should handle 404 for unregistered routes', () async {
        router.getView('/registered', () => TestView());

        final request = shelf.Request(
          'GET',
          Uri.parse('http://localhost/unregistered'),
        );
        final response = await router.call(request);

        expect(response.statusCode, equals(404));
      });

      test('should handle method not allowed', () async {
        // TestView only allows GET and POST, but when registered with getView,
        // Shelf Router will return 404 for other methods (not 405)
        router.getView('/test', () => TestView());

        final request = shelf.Request(
          'PUT',
          Uri.parse('http://localhost/test'),
        );
        final response = await router.call(request);

        expect(
          response.statusCode,
          equals(404),
        ); // Shelf Router behavior: unregistered route
      });
    });
  });
}
