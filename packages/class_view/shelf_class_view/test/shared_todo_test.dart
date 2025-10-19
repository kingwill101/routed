import 'dart:convert';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:todo_test/todo_test.dart';

/// Create the Todo app with Shelf and class view extensions
shelf.Handler _createShelfTodoApp(TodoRepository repository) {
  final router = Router();

  // ✨ Clean route registration using shelf class_view extensions!

  // List todos (with pagination, filtering, search)
  router.getView('/todos', () => TodoListView(repository));

  // Create todo (handles both GET for form info and POST for creation)
  router.allView('/todos/create', () => TodoCreateView(repository));

  // Detail view for single todo
  router.getView('/todos/<id>', () => TodoDetailView(repository));

  // Update todo (handles GET for form info, PUT for updates)
  router.allView('/todos/<id>/edit', () => TodoUpdateView(repository));
  router.putView('/todos/<id>', () => TodoUpdateView(repository));

  // Delete todo (handles GET for confirmation, DELETE for deletion)
  router.allView('/todos/<id>/delete', () => TodoDeleteView(repository));
  router.deleteView('/todos/<id>', () => TodoDeleteView(repository));

  return router.call;
}

void main() {
  group('Shelf Class View - Todo App Server Testing Integration', () {
    runTodoServerTests(() {
      // Create repository and app for each test
      final repository = TodoRepository();
      final app = _createShelfTodoApp(repository);
      final handler = ShelfRequestHandler(app);

      return (handler, repository);
    });
  });

  group('Shared Todo Tests', () {
    late ShelfAdapter adapter;
    late shelf.Request request;

    setUp(() {
      // Create a basic request for testing
      request = shelf.Request(
        'GET',
        Uri.parse('http://localhost:8080/test?param1=value1&param2=value2'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer token123',
        },
        body: Stream.value(utf8.encode('{"name": "John", "age": 30}')),
      );

      final routeParams = {'id': '123', 'category': 'posts'};
      adapter = ShelfAdapter(request, routeParams);
    });

    group('Request Information', () {
      test('should return correct HTTP method', () async {
        expect(await adapter.getMethod(), equals('GET'));
      });

      test('should return correct URI', () async {
        expect(
          (await adapter.getUri()).toString(),
          equals('http://localhost:8080/test?param1=value1&param2=value2'),
        );
      });

      test(
        'should get route parameters first, then query parameters',
        () async {
          expect(await adapter.getParam('id'), equals('123')); // Route param
          expect(
            await adapter.getParam('param1'),
            equals('value1'),
          ); // Query param
          expect(await adapter.getParam('nonexistent'), isNull);
        },
      );

      test('should return all parameters (route + query)', () async {
        final params = await adapter.getParams();
        expect(params, containsPair('id', '123'));
        expect(params, containsPair('category', 'posts'));
        expect(params, containsPair('param1', 'value1'));
        expect(params, containsPair('param2', 'value2'));
      });

      test('should return only query parameters', () async {
        final queryParams = await adapter.getQueryParams();
        expect(queryParams, containsPair('param1', 'value1'));
        expect(queryParams, containsPair('param2', 'value2'));
        expect(queryParams, isNot(containsPair('id', '123')));
      });

      test('should return only route parameters', () async {
        final routeParams = await adapter.getRouteParams();
        expect(routeParams, containsPair('id', '123'));
        expect(routeParams, containsPair('category', 'posts'));
        expect(routeParams, isNot(containsPair('param1', 'value1')));
      });

      test('should return request headers', () async {
        final headers = await adapter.getHeaders();
        expect(headers, containsPair('content-type', 'application/json'));
        expect(headers, containsPair('authorization', 'Bearer token123'));
      });

      test('should get specific header', () async {
        expect(
          await adapter.getHeader('content-type'),
          equals('application/json'),
        );
        expect(
          await adapter.getHeader('Content-Type'),
          equals('application/json'),
        ); // Case insensitive
        expect(await adapter.getHeader('nonexistent'), isNull);
      });

      test('should read request body as string', () async {
        final body = await adapter.getBody();
        expect(body, equals('{"name": "John", "age": 30}'));
      });

      test('should parse JSON body', () async {
        final jsonBody = await adapter.getJsonBody();
        expect(jsonBody, isA<Map<String, dynamic>>());
        expect(jsonBody['name'], equals('John'));
        expect(jsonBody['age'], equals(30));
      });

      test('should handle empty JSON body', () async {
        final emptyRequest = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
          body: Stream.value(utf8.encode('')),
        );
        final emptyAdapter = ShelfAdapter(emptyRequest);

        final jsonBody = await emptyAdapter.getJsonBody();
        expect(jsonBody, isEmpty);
      });

      test('should throw FormatException for invalid JSON', () async {
        final invalidJsonRequest = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
          body: Stream.value(utf8.encode('invalid json')),
        );
        final invalidAdapter = ShelfAdapter(invalidJsonRequest);

        expect(
          () => invalidAdapter.getJsonBody(),
          throwsA(isA<FormatException>()),
        );
      });

      test('should parse URL-encoded form data', () async {
        final formRequest = shelf.Request(
          'POST',
          Uri.parse('http://localhost/test'),
          headers: {'content-type': 'application/x-www-form-urlencoded'},
          body: Stream.value(utf8.encode('name=John&age=30&city=New%20York')),
        );
        final formAdapter = ShelfAdapter(formRequest);

        final formData = await formAdapter.getFormData();
        expect(formData['name'], equals('John'));
        expect(formData['age'], equals('30'));
        expect(formData['city'], equals('New York'));
      });

      test('should handle JSON as form data', () async {
        final formData = await adapter.getFormData();
        expect(formData['name'], equals('John'));
        expect(formData['age'], equals(30));
      });

      test('should handle request without body', () async {
        final noBodyRequest = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
          body: Stream.value(utf8.encode('')),
        );
        final noBodyAdapter = ShelfAdapter(noBodyRequest);

        final body = await noBodyAdapter.getBody();
        expect(body, isEmpty);

        // Create a new request for JSON body test since Shelf requests can only be read once
        final noBodyRequest2 = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
          body: Stream.value(utf8.encode('')),
        );
        final noBodyAdapter2 = ShelfAdapter(noBodyRequest2);

        final jsonBody = await noBodyAdapter2.getJsonBody();
        expect(jsonBody, isEmpty);
      });
    });

    group('Response Operations', () {
      test('should set status code', () async {
        adapter.setStatusCode(404);
        final response = adapter.buildResponse();
        expect(response.statusCode, equals(404));
      });

      test('should set headers', () async {
        await adapter.setHeader('X-Custom-Header', 'custom-value');
        await adapter.setHeader('Content-Type', 'text/plain');

        final response = adapter.buildResponse();
        expect(response.headers['X-Custom-Header'], equals('custom-value'));
        expect(response.headers['Content-Type'], equals('text/plain'));
      });

      test('should write body content', () async {
        await adapter.write('Hello, ');
        await adapter.write('World!');

        final response = adapter.buildResponse();
        expect(response.readAsString(), completion(equals('Hello, World!')));
      });

      test('should write JSON response', () async {
        final data = {'message': 'Hello', 'status': 'success'};
        await adapter.writeJson(data, statusCode: 201);

        final response = adapter.buildResponse();
        expect(response.statusCode, equals(201));
        final contentType =
            response.headers['Content-Type'] ??
            response.headers['content-type'];
        expect(contentType, equals('application/json; charset=utf-8'));

        return response.readAsString().then((body) {
          final decodedBody = json.decode(body);
          expect(decodedBody['message'], equals('Hello'));
          expect(decodedBody['status'], equals('success'));
        });
      });

      test('should handle redirect', () async {
        await adapter.redirect('/new-location', statusCode: 301);

        final response = adapter.buildResponse();
        expect(response.statusCode, equals(301));
        expect(response.headers['Location'], equals('/new-location'));
        expect(response.readAsString(), completion(equals('')));
      });

      test('should use default redirect status code', () async {
        await adapter.redirect('/new-location');

        final response = adapter.buildResponse();
        expect(response.statusCode, equals(302));
      });
    });

    group('Lifecycle', () {
      test('setup should complete without error', () async {
        expect(() => adapter.setup(), returnsNormally);
        await adapter.setup();
      });

      test('teardown should complete without error', () async {
        expect(() => adapter.teardown(), returnsNormally);
        await adapter.teardown();
      });
    });

    group('Static methods', () {
      test(
        'fromRequest should create adapter with empty route params',
        () async {
          final newAdapter = ShelfAdapter.fromRequest(request);
          expect(await newAdapter.getRouteParams(), isEmpty);
          expect(await newAdapter.getMethod(), equals('GET'));
        },
      );

      test(
        'fromRequest should create adapter with provided route params',
        () async {
          final routeParams = {'userId': '456'};
          final newAdapter = ShelfAdapter.fromRequest(request, routeParams);
          expect(
            await newAdapter.getRouteParams(),
            containsPair('userId', '456'),
          );
        },
      );
    });

    group('Edge cases', () {
      test('should handle request without headers', () async {
        final noHeaderRequest = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
        );
        final noHeaderAdapter = ShelfAdapter(noHeaderRequest);

        expect(await noHeaderAdapter.getHeader('content-type'), isNull);
        expect(await noHeaderAdapter.getHeaders(), isA<Map<String, String>>());
      });

      test('should handle request without query parameters', () async {
        final noQueryRequest = shelf.Request(
          'GET',
          Uri.parse('http://localhost/test'),
        );
        final noQueryAdapter = ShelfAdapter(noQueryRequest);

        expect(await noQueryAdapter.getQueryParams(), isEmpty);
        expect(await noQueryAdapter.getParam('nonexistent'), isNull);
      });

      test('should handle different HTTP methods', () async {
        final methods = ['POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'];

        for (final method in methods) {
          final methodRequest = shelf.Request(
            method,
            Uri.parse('http://localhost/test'),
          );
          final methodAdapter = ShelfAdapter(methodRequest);
          expect(await methodAdapter.getMethod(), equals(method));
        }
      });
    });
  });

  group('ShelfAdapter Multipart Tests', () {
    test('should parse multipart form data correctly', () async {
      // Create a multipart request with a file and a text field
      final boundary = 'boundary123';
      final fileContent = 'Hello, World!';
      final fileBytes = utf8.encode(fileContent);
      final formData =
          '''
--$boundary
Content-Disposition: form-data; name="file"; filename="test.txt"
Content-Type: text/plain

$fileContent
--$boundary
Content-Disposition: form-data; name="text"

This is a text field
--$boundary--
''';
      final request = shelf.Request(
        'POST',
        Uri.parse('http://localhost:8080/upload'),
        headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
        body: Stream.value(utf8.encode(formData)),
      );

      // Create the adapter
      final adapter = ShelfAdapter.fromRequest(request);

      // Get form data
      final formDataResult = await adapter.getFormData();

      // Verify file upload
      expect(formDataResult['file'], isA<List>());
      final fileList = formDataResult['file'] as List;
      expect(fileList.length, 1);
      final file = fileList.first as FormFile;
      expect(file.name, 'file');
      if ((file as dynamic).filename != null) {
        expect((file as dynamic).filename, 'test.txt');
      }
      expect(file.size, fileBytes.length);
      expect(file.contentType, 'text/plain');
      expect(file.content, fileBytes);

      // Verify text field
      expect(formDataResult['text'], 'This is a text field');
    });

    test('should handle multiple files with the same field name', () async {
      final boundary = 'boundary123';
      final file1Content = 'File 1 content';
      final file2Content = 'File 2 content';
      final formData =
          '''
--$boundary
Content-Disposition: form-data; name="files"; filename="file1.txt"
Content-Type: text/plain

$file1Content
--$boundary
Content-Disposition: form-data; name="files"; filename="file2.txt"
Content-Type: text/plain

$file2Content
--$boundary--
''';
      final request = shelf.Request(
        'POST',
        Uri.parse('http://localhost:8080/upload'),
        headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
        body: Stream.value(utf8.encode(formData)),
      );

      final adapter = ShelfAdapter.fromRequest(request);
      final formDataResult = await adapter.getFormData();

      expect(formDataResult['files'], isA<List>());
      final fileList = formDataResult['files'] as List;
      expect(fileList.length, 2);
      if ((fileList[0] as dynamic).filename != null) {
        expect((fileList[0] as dynamic).filename, 'file1.txt');
      }
      if ((fileList[1] as dynamic).filename != null) {
        expect((fileList[1] as dynamic).filename, 'file2.txt');
      }
    });

    test('should handle non-multipart requests gracefully', () async {
      final request = shelf.Request(
        'POST',
        Uri.parse('http://localhost:8080/upload'),
        headers: {'content-type': 'application/json'},
        body: Stream.value(utf8.encode(json.encode({'key': 'value'}))),
      );

      final adapter = ShelfAdapter.fromRequest(request);
      final formDataResult = await adapter.getFormData();

      expect(formDataResult, {'key': 'value'});
    });
  });
}
