import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

/// Test TemplateView implementation
class TestTemplateView extends TemplateView {
  @override
  String get templateName => 'test_template.html';

  @override
  Future<Map<String, dynamic>> getContextData() async {
    return {
      'title': 'Test Page',
      'message': 'Hello, World!',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    // Mock implementation that sends JSON instead of actual template rendering
    sendJson({
      'template': templateName ?? this.templateName,
      'context': templateContext,
      'status': statusCode,
    }, statusCode: statusCode);
  }
}

/// Test TemplateView with custom context
class CustomContextTemplateView extends TemplateView {
  final String customTitle;

  CustomContextTemplateView(this.customTitle);

  @override
  String? get templateName => 'custom_template.html';

  @override
  ViewEngine? get viewEngine => null; // Mock implementation

  @override
  Future<Map<String, dynamic>> getContextData() async {
    return {
      'title': customTitle,
      'user': {'id': 1, 'name': 'John Doe'},
      'settings': await _loadSettings(),
    };
  }

  Future<Map<String, dynamic>> _loadSettings() async {
    // Simulate async settings loading
    await Future.delayed(Duration(milliseconds: 5));
    return {'theme': 'dark', 'lang': 'en'};
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    sendJson({
      'template': templateName ?? this.templateName,
      'context': templateContext,
      'status': statusCode,
    }, statusCode: statusCode);
  }
}

/// Test TemplateView that throws an error during context building
class ErrorContextTemplateView extends TemplateView {
  @override
  String? get templateName => 'error_template.html';

  @override
  ViewEngine? get viewEngine => null; // Mock implementation

  @override
  Future<Map<String, dynamic>> getContextData() async {
    throw Exception('Context loading failed');
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    sendJson({
      'template': templateName ?? this.templateName,
      'context': templateContext,
      'status': statusCode,
    }, statusCode: statusCode);
  }
}

/// Test TemplateView that throws an error during rendering
class ErrorRenderTemplateView extends TemplateView {
  @override
  String? get templateName => 'render_error_template.html';

  @override
  ViewEngine? get viewEngine => null; // Mock implementation

  @override
  Future<Map<String, dynamic>> getContextData() async {
    return {'title': 'Test'};
  }

  @override
  Future<void> renderToResponse(
    Map<String, dynamic> templateContext, {
    String? templateName,
    int statusCode = 200,
  }) async {
    throw Exception('Template rendering failed');
  }
}

void main() {
  group('TemplateView Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
    });

    group('Basic Functionality', () {
      test('should have GET as allowed method by default', () {
        final view = TestTemplateView();
        expect(view.allowedMethods, contains('GET'));
      });

      test('should provide template name', () {
        final view = TestTemplateView();
        expect(view.templateName, equals('test_template.html'));
      });

      test('should handle custom template names', () {
        final view = CustomContextTemplateView('Custom Title');
        expect(view.templateName, equals('custom_template.html'));
      });
    });

    group('Context Building', () {
      test('should build basic context data', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context['title'], equals('Test Page'));
        expect(context['message'], equals('Hello, World!'));
        expect(context['timestamp'], isA<int>());
      });

      test('should build custom context data', () async {
        final view = CustomContextTemplateView('My Custom Title');
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context['title'], equals('My Custom Title'));
        expect(context['user'], isA<Map<String, dynamic>>());
        expect(context['user']['name'], equals('John Doe'));
        expect(context['settings'], isA<Map<String, dynamic>>());
        expect(context['settings']['theme'], equals('dark'));
      });

      test('should handle async context building', () async {
        final view = CustomContextTemplateView('Async Test');
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        // Settings should be loaded asynchronously
        expect(context['settings']['lang'], equals('en'));
      });

      test('should handle context building errors', () async {
        final view = ErrorContextTemplateView();
        view.setAdapter(mockAdapter);

        expect(() => view.getContextData(), throwsA(isA<Exception>()));
      });
    });

    group('Template Rendering', () {
      test('should render template with context', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        final context = {'test': 'data'};
        await view.renderToResponse(context);

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['template'], equals('test_template.html'));
        expect(responseData['context'], equals(context));
        expect(responseData['status'], equals(200));
      });

      test('should use custom template name when provided', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        final context = {'test': 'data'};
        await view.renderToResponse(context, templateName: 'custom.html');

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['template'], equals('custom.html'));
      });

      test('should use custom status code when provided', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        final context = {'test': 'data'};
        await view.renderToResponse(context, statusCode: 201);

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['status'], equals(201));
      });

      test('should handle rendering errors', () async {
        final view = ErrorRenderTemplateView();
        view.setAdapter(mockAdapter);

        final context = {'test': 'data'};

        expect(() => view.renderToResponse(context), throwsA(isA<Exception>()));
      });
    });

    group('GET Request Handling', () {
      test('should handle successful GET request', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await view.dispatch();

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['template'], equals('test_template.html'));
        expect(responseData['context'], isA<Map<String, dynamic>>());
        expect(responseData['context']['title'], equals('Test Page'));
      });

      test('should handle GET request with custom context', () async {
        final view = CustomContextTemplateView('Page Title');
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await view.dispatch();

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['context']['title'], equals('Page Title'));
        expect(responseData['context']['user']['name'], equals('John Doe'));
      });

      test('should handle errors during GET request', () async {
        final view = ErrorContextTemplateView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await view.dispatch();

        // Should have sent an error response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Method Restrictions', () {
      test('should reject POST requests by default', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');

        await view.dispatch();

        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject PUT requests by default', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PUT');

        await view.dispatch();

        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject DELETE requests by default', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'DELETE');

        await view.dispatch();

        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Integration Tests', () {
      test('should work with mixin functionality', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        // Should be able to call template-specific methods
        expect(view.templateName, isA<String>());

        final context = await view.getContextData();
        expect(context, isA<Map<String, dynamic>>());

        await view.renderToResponse(context);
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Edge Cases', () {
      test('should handle empty context', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        await view.renderToResponse({});

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['context'], equals({}));
      });

      test('should handle null values in context', () async {
        final view = TestTemplateView();
        view.setAdapter(mockAdapter);

        final context = {'nullable': null, 'string': 'value'};
        await view.renderToResponse(context);

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['context']['nullable'], isNull);
        expect(responseData['context']['string'], equals('value'));
      });
    });
  });
}
