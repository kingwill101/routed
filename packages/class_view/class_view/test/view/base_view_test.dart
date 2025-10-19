import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

/// Test view that implements the abstract View class
class TestView extends View {
  @override
  List<String> get allowedMethods => ['GET', 'POST', 'PUT', 'DELETE'];

  @override
  Future<void> get() async {
    sendJson({'method': 'GET', 'message': 'Hello from GET'});
  }

  @override
  Future<void> post() async {
    final body = await getJsonBody();
    sendJson({'method': 'POST', 'received': body});
  }

  @override
  Future<void> put() async {
    final body = await getJsonBody();
    sendJson({'method': 'PUT', 'updated': body});
  }

  @override
  Future<void> delete() async {
    sendJson({'method': 'DELETE', 'message': 'Deleted'});
  }
}

/// Test view that only allows GET method
class GetOnlyView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    sendJson({'message': 'GET only view'});
  }
}

/// Test view that throws an error
class ErrorView extends View {
  @override
  Future<void> get() async {
    throw Exception('Test error');
  }
}

void main() {
  group('Base View Tests', () {
    late MockViewAdapter mockAdapter;
    late TestView view;

    setUp(() {
      mockAdapter = MockViewAdapter();
      view = TestView();
      view.setAdapter(mockAdapter);
    });

    group('Adapter Management', () {
      test('should set and get adapter', () {
        final newAdapter = MockViewAdapter();
        view.setAdapter(newAdapter);
        expect(view.adapter, equals(newAdapter));
      });

      test('should throw error if no adapter is set', () {
        final viewWithoutAdapter = TestView();
        expect(() => viewWithoutAdapter.adapter, throwsStateError);
      });
    });

    group('Request Delegation', () {
      test('should delegate method to adapter', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        expect(await view.getMethod(), equals('POST'));
        verify(mockAdapter.getMethod()).called(1);
      });

      test('should delegate uri to adapter', () async {
        final testUri = Uri.parse('http://localhost/test');
        when(mockAdapter.getUri()).thenAnswer((_) async => testUri);
        expect(await view.getUri(), equals(testUri));
        verify(mockAdapter.getUri()).called(1);
      });

      test('should delegate getParam to adapter', () async {
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '123');
        expect(await view.getParam('id'), equals('123'));
        verify(mockAdapter.getParam('id')).called(1);
      });

      test('should delegate getParams to adapter', () async {
        final params = {'id': '123', 'name': 'test'};
        when(mockAdapter.getParams()).thenAnswer((_) async => params);
        expect(await view.getParams(), equals(params));
        verify(mockAdapter.getParams()).called(1);
      });

      test('should delegate getQueryParams to adapter', () async {
        final queryParams = {'page': '1', 'size': '10'};
        when(mockAdapter.getQueryParams()).thenAnswer((_) async => queryParams);
        expect(await view.getQueryParams(), equals(queryParams));
        verify(mockAdapter.getQueryParams()).called(1);
      });

      test('should delegate getRouteParams to adapter', () async {
        final routeParams = {'id': '123'};
        when(mockAdapter.getRouteParams()).thenAnswer((_) async => routeParams);
        expect(await view.getRouteParams(), equals(routeParams));
        verify(mockAdapter.getRouteParams()).called(1);
      });

      test('should delegate getHeaders to adapter', () async {
        final headers = {'Content-Type': 'application/json'};
        when(mockAdapter.getHeaders()).thenAnswer((_) async => headers);
        expect(await view.getHeaders(), equals(headers));
        verify(mockAdapter.getHeaders()).called(1);
      });

      test('should delegate getHeader to adapter', () async {
        when(
          mockAdapter.getHeader('Content-Type'),
        ).thenAnswer((_) async => 'application/json');
        expect(
          await view.getHeader('Content-Type'),
          equals('application/json'),
        );
        verify(mockAdapter.getHeader('Content-Type')).called(1);
      });

      test('should delegate getBody to adapter', () async {
        when(mockAdapter.getBody()).thenAnswer((_) async => 'test body');
        final body = await view.getBody();
        expect(body, equals('test body'));
        verify(mockAdapter.getBody()).called(1);
      });

      test('should delegate getJsonBody to adapter', () async {
        final jsonData = {'name': 'test'};
        when(mockAdapter.getJsonBody()).thenAnswer((_) async => jsonData);
        final body = await view.getJsonBody();
        expect(body, equals(jsonData));
        verify(mockAdapter.getJsonBody()).called(1);
      });

      test('should delegate getFormData to adapter', () async {
        final formData = {'field1': 'value1'};
        when(mockAdapter.getFormData()).thenAnswer((_) async => formData);
        final data = await view.getFormData();
        expect(data, equals(formData));
        verify(mockAdapter.getFormData()).called(1);
      });
    });

    group('Response Operations', () {
      test('should delegate setStatusCode to adapter', () {
        view.setStatusCode(404);
        verify(mockAdapter.setStatusCode(404)).called(1);
      });

      test('should delegate setHeader to adapter', () {
        view.setHeader('X-Custom', 'value');
        verify(mockAdapter.setHeader('X-Custom', 'value')).called(1);
      });

      test('should delegate write to adapter', () {
        view.write('test content');
        verify(mockAdapter.write('test content')).called(1);
      });

      test('should delegate sendJson to adapter', () {
        final data = {'message': 'success'};
        view.sendJson(data, statusCode: 201);
        verify(mockAdapter.writeJson(data, statusCode: 201)).called(1);
      });

      test('should delegate redirect to adapter', () {
        view.redirect('/new-location', statusCode: 301);
        verify(
          mockAdapter.redirect('/new-location', statusCode: 301),
        ).called(1);
      });
    });

    group('HTTP Method Dispatch', () {
      test('should dispatch GET request', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await view.dispatch();

        verify(
          mockAdapter.writeJson({
            'method': 'GET',
            'message': 'Hello from GET',
          }, statusCode: 200),
        ).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should dispatch POST request', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getJsonBody(),
        ).thenAnswer((_) async => {'data': 'test'});

        await view.dispatch();

        verify(
          mockAdapter.writeJson({
            'method': 'POST',
            'received': {'data': 'test'},
          }, statusCode: 200),
        ).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should dispatch PUT request', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PUT');
        when(
          mockAdapter.getJsonBody(),
        ).thenAnswer((_) async => {'id': 1, 'name': 'updated'});

        await view.dispatch();

        verify(
          mockAdapter.writeJson({
            'method': 'PUT',
            'updated': {'id': 1, 'name': 'updated'},
          }, statusCode: 200),
        ).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should dispatch DELETE request', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'DELETE');

        await view.dispatch();

        verify(
          mockAdapter.writeJson({
            'method': 'DELETE',
            'message': 'Deleted',
          }, statusCode: 200),
        ).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should return 405 for method not allowed', () async {
        final getOnlyView = GetOnlyView();
        getOnlyView.setAdapter(mockAdapter);
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');

        await getOnlyView.dispatch();

        verify(mockAdapter.writeJson(any, statusCode: 405)).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should handle unsupported method', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PATCH');

        await view.dispatch();

        verify(mockAdapter.writeJson(any, statusCode: 405)).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });
    });

    group('Error Handling', () {
      test('should handle view exceptions gracefully', () async {
        final errorView = ErrorView();
        errorView.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await errorView.dispatch();

        // Check that an error response was sent
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should handle adapter setup/teardown', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await view.dispatch();

        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });

      test('should call teardown even if dispatch fails', () async {
        final errorView = ErrorView();
        errorView.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await errorView.dispatch();

        verify(mockAdapter.setup()).called(1);
        verify(mockAdapter.teardown()).called(1);
      });
    });

    group('Convenience Properties and Methods', () {
      test('should provide request helper object', () async {
        final req = view.request();
        expect(req, isNotNull);
        expect(await req.getMethod(), equals(await view.getMethod()));
      });

      test('should provide response helper object', () {
        final resp = view.response();
        expect(resp, isNotNull);
      });

      test('should check allowed methods', () {
        expect(view.allowedMethods, contains('GET'));
        expect(view.allowedMethods, contains('POST'));
        expect(view.allowedMethods, contains('PUT'));
        expect(view.allowedMethods, contains('DELETE'));
      });
    });

    group('Renderer Management', () {
      test('should set and get renderer', () {
        // This would require a mock renderer, but testing the basic functionality
        expect(view.renderer, isNull);

        // view.setRenderer(someRenderer); // Would test if we had a renderer
        // expect(view.renderer, isNotNull);
      });
    });

    group('Default Method Implementations', () {
      test(
        'should return 405 for unimplemented methods in minimal view',
        () async {
          final minimalView = _MinimalView();
          minimalView.setAdapter(mockAdapter);

          when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

          await minimalView.dispatch();

          // Check that an error response was sent due to method not allowed
          verify(
            mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
          ).called(1);
        },
      );
    });
  });
}

/// Minimal view with no implemented methods for testing defaults
class _MinimalView extends View {
  @override
  List<String> get allowedMethods => [];
}
