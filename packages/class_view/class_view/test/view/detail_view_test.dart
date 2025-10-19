import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

// Test model
class Post {
  final int id;
  final String title;
  final String content;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Test DetailView implementation
class TestPostDetailView extends DetailView<Post> {
  final Map<String, Post> _posts = {
    '1': Post(
      id: 1,
      title: 'Test Post',
      content: 'This is a test post',
      createdAt: DateTime(2024, 1, 1),
    ),
    '2': Post(
      id: 2,
      title: 'Another Post',
      content: 'Another test post',
      createdAt: DateTime(2024, 1, 2),
    ),
  };

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return _posts[id];
  }
}

/// Test DetailView with custom context object name
class CustomPostDetailView extends DetailView<Post> {
  final Map<String, Post> _posts = {
    '1': Post(
      id: 1,
      title: 'Custom Post',
      content: 'Custom content',
      createdAt: DateTime(2024, 1, 1),
    ),
  };

  @override
  String? get contextObjectName => 'article';

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return _posts[id];
  }
}

/// Test DetailView that always returns null (404 case)
class NotFoundDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    return null;
  }
}

/// Test DetailView that throws an error
class ErrorDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    throw Exception('Database error');
  }
}

void main() {
  group('DetailView Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
    });

    group('Basic Functionality', () {
      test('should have GET as allowed method', () {
        final view = TestPostDetailView();
        expect(view.allowedMethods, contains('GET'));
        expect(view.allowedMethods.length, equals(1));
      });

      test('should use default lookup parameter "id"', () {
        final view = TestPostDetailView();
        expect(view.lookupParam, equals('id'));
      });

      test('should use class name as default context object name', () {
        final view = TestPostDetailView();
        expect(view.getContextObjectName(), equals('post'));
      });

      test('should allow custom context object name', () {
        final view = CustomPostDetailView();
        expect(view.getContextObjectName(), equals('article'));
      });
    });

    group('Object Retrieval', () {
      test('should retrieve object by ID parameter', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        final post = await view.getObject();

        expect(post, isNotNull);
        expect(post!.id, equals(1));
        expect(post.title, equals('Test Post'));
      });

      test('should return null for non-existent object', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '999');

        final post = await view.getObject();
        expect(post, isNull);
      });

      test(
        'should throw 404 for getObjectOr404 when object not found',
        () async {
          final view = NotFoundDetailView();
          view.setAdapter(mockAdapter);

          when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

          expect(() => view.getObjectOr404(), throwsA(isA<HttpException>()));
        },
      );

      test(
        'should return object for getObjectOr404 when object exists',
        () async {
          final view = TestPostDetailView();
          view.setAdapter(mockAdapter);

          when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

          final post = await view.getObjectOr404();

          expect(post, isNotNull);
          expect(post.id, equals(1));
        },
      );
    });

    group('Context Building', () {
      test('should build context with object', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        final context = await view.getContextData();

        expect(context['post'], isA<Post>());
        expect(context['post'].id, equals(1));
        expect(context['post'].title, equals('Test Post'));
      });

      test('should use custom context object name', () async {
        final view = CustomPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        final context = await view.getContextData();

        expect(context['article'], isA<Post>());
        expect(context['article'].id, equals(1));
        expect(context['article'].title, equals('Custom Post'));
      });

      test('should handle 404 case in context building', () async {
        final view = NotFoundDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        // Should throw when building context because getObjectOr404 is called
        expect(() => view.getContextData(), throwsA(isA<HttpException>()));
      });
    });

    group('GET Request Handling', () {
      test('should handle successful GET request', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        await view.dispatch();

        // Verify response was sent with context data
        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['post'], isA<Post>());
        expect(responseData['post'].id, equals(1));
        expect(responseData['post'].title, equals('Test Post'));
      });

      test('should handle 404 for non-existent object', () async {
        final view = NotFoundDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        await view.dispatch();

        // Should have sent an error response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should handle errors gracefully', () async {
        final view = ErrorDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        await view.dispatch();

        // Should have sent an error response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Method Restrictions', () {
      test('should reject POST requests', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');

        await view.dispatch();

        // Should have sent a method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject PUT requests', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PUT');

        await view.dispatch();

        // Should have sent a method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject DELETE requests', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'DELETE');

        await view.dispatch();

        // Should have sent a method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Integration with Mixins', () {
      test('should work with ContextMixin functionality', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '2');

        final context = await view.getContextData();

        // Should have mixin functionality
        expect(context['post'], isA<Post>()); // From SingleObjectMixin
        expect(context['post'].id, equals(2));
        expect(context['post'].title, equals('Another Post'));
      });
    });

    group('Edge Cases', () {
      test('should handle null ID parameter', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => null);

        final post = await view.getObject();
        expect(post, isNull);
      });

      test('should handle empty ID parameter', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '');

        final post = await view.getObject();
        expect(post, isNull);
      });

      test('should handle concurrent requests', () async {
        final view = TestPostDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        // Multiple concurrent calls should work
        final futures = List.generate(5, (_) => view.getObject());
        final results = await Future.wait(futures);

        for (final post in results) {
          expect(post, isNotNull);
          expect(post!.id, equals(1));
        }
      });
    });
  });
}
