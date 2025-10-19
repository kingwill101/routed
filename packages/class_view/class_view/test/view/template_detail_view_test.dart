import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

// Test model (reusing from other tests)
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

/// Test TemplateDetailView implementation
class TestPostTemplateDetailView extends TemplateDetailView<Post> {
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

  TestPostTemplateDetailView();

  @override
  String? get templateName => 'post_detail.html';

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    print('TestPostTemplateDetailView.getObject() called with id: $id');
    final post = _posts[id];
    print('TestPostTemplateDetailView.getObject() returning: $post');
    return post;
  }
}

/// Test TemplateDetailView with custom object name
class CustomObjectTemplateDetailView extends TemplateDetailView<Post> {
  final Map<String, Post> _posts = {
    '1': Post(
      id: 1,
      title: 'Custom Post',
      content: 'Custom content',
      createdAt: DateTime(2024, 1, 1),
    ),
  };

  CustomObjectTemplateDetailView();

  @override
  String? get templateName => 'article_detail.html';

  @override
  String? get contextObjectName => 'article';

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return _posts[id];
  }
}

/// Test TemplateDetailView with additional context data
class RichContextTemplateDetailView extends TemplateDetailView<Post> {
  final Map<String, Post> _posts = {
    '1': Post(
      id: 1,
      title: 'Rich Post',
      content: 'Rich content',
      createdAt: DateTime(2024, 1, 1),
    ),
  };

  RichContextTemplateDetailView();

  @override
  String? get templateName => 'rich_detail.html';

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return _posts[id];
  }

  @override
  Future<Map<String, dynamic>> getContextData() async {
    final baseContext = await super.getContextData();
    return {
      ...baseContext,
      'site_name': 'My Blog',
      'author': 'John Doe',
      'meta_description': 'A detailed post view',
      'related_posts': await _getRelatedPosts(),
      'comment_count': 42,
    };
  }

  Future<List<Map<String, dynamic>>> _getRelatedPosts() async {
    // Simulate loading related posts
    return [
      {'id': 2, 'title': 'Related Post 1'},
      {'id': 3, 'title': 'Related Post 2'},
    ];
  }
}

/// Test TemplateDetailView that always returns null (404 case)
class NotFoundTemplateDetailView extends TemplateDetailView<Post> {
  NotFoundTemplateDetailView();

  @override
  String? get templateName => 'not_found.html';

  @override
  Future<Post?> getObject() async {
    return null;
  }
}

/// Test TemplateDetailView that throws an error
class ErrorTemplateDetailView extends TemplateDetailView<Post> {
  ErrorTemplateDetailView();

  @override
  String? get templateName => 'error_detail.html';

  @override
  Future<Post?> getObject() async {
    throw Exception('Database error');
  }
}

void main() {
  group('TemplateDetailView Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
      // Configure TemplateManager for testing
      TemplateManager.configureMemoryOnly();
    });

    tearDown(() {
      // Reset TemplateManager after each test
      TemplateManager.reset();
    });

    group('Basic Functionality', () {
      test('should have GET as allowed method', () {
        final view = TestPostTemplateDetailView();
        expect(view.allowedMethods, contains('GET'));
        expect(view.allowedMethods.length, equals(1));
      });

      test('should store template name', () {
        final view = TestPostTemplateDetailView();
        expect(view.templateName, equals('post_detail.html'));
      });

      test('should use default object name "post"', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        expect(context['post'], isNotNull);
      });

      test('should allow custom object name', () async {
        final view = CustomObjectTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        expect(context['article'], isNotNull);
      });

      test('should use default lookup parameter "id"', () {
        final view = TestPostTemplateDetailView();
        expect(view.lookupParam, equals('id'));
      });
    });

    group('Object Retrieval', () {
      test('should retrieve object by ID parameter', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        final post = await view.getObject();

        expect(post, isNotNull);
        expect(post!.id, equals(1));
        expect(post.title, equals('Test Post'));
      });

      test('should return null for non-existent ID', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '999');

        final post = await view.getObject();
        expect(post, isNull);
      });

      test('should throw 404 for non-existent object', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '999');

        expect(
          () => view.getObjectOr404(),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'message',
              'Object not found',
            ),
          ),
        );
      });
    });

    group('Context Building', () {
      test('should build context with object', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        expect(context['post'], isA<Post>());
        expect(context['post'].id, equals(1));
        expect(context['post'].title, equals('Test Post'));
      });

      test('should use custom context object name', () async {
        final view = CustomObjectTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');

        final context = await view.getContextData();

        expect(context['article'], isA<Post>());
        final post = context['article'] as Post;
        expect(post.id, equals(1));
        expect(post.title, equals('Custom Post'));
      });

      test('should include additional context data', () async {
        final view = RichContextTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        expect(context['post'], isA<Post>());
        expect(context['site_name'], equals('My Blog'));
        expect(context['author'], equals('John Doe'));
        expect(context['meta_description'], equals('A detailed post view'));
        expect(context['related_posts'], isA<List>());
        expect(context['comment_count'], equals(42));
      });
    });

    group('Template Integration', () {
      test('should provide template name to parent class', () {
        final view = TestPostTemplateDetailView();
        expect(view.templateName, equals('post_detail.html'));
      });

      test('should support different template names', () {
        final customView = CustomObjectTemplateDetailView();
        expect(customView.templateName, equals('article_detail.html'));

        final richView = RichContextTemplateDetailView();
        expect(richView.templateName, equals('rich_detail.html'));
      });
    });

    group('GET Request Handling', () {
      test('should handle successful GET request', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        await view.dispatch();
        verify(mockAdapter.write(any)).called(1);
      });

      test('should handle 404 for non-existent object', () async {
        final view = NotFoundTemplateDetailView();
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
        final view = ErrorTemplateDetailView();
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
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');

        await view.dispatch();

        // Should have sent a method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject PUT requests', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PUT');

        await view.dispatch();

        // Should have sent a method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject DELETE requests', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'DELETE');

        await view.dispatch();

        // Should have sent a method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Context Data Manipulation', () {
      test('should allow modification of contextData property', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        context['custom_field'] = 'custom_value';
        expect(context['custom_field'], equals('custom_value'));
      });

      test('should merge contextData with object context', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        context['additional_info'] = 'test_info';
        expect(context['post'], isA<Post>());
        expect(context['additional_info'], equals('test_info'));
      });
    });

    group('Edge Cases', () {
      test('should handle null ID parameter', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => null);

        final post = await view.getObject();
        expect(post, isNull);
      });

      test('should handle empty ID parameter', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '');

        final post = await view.getObject();
        expect(post, isNull);
      });

      test('should handle concurrent requests', () async {
        final view = TestPostTemplateDetailView();
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

    group('Integration with DetailView', () {
      test('should inherit DetailView functionality', () async {
        final view = TestPostTemplateDetailView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('id')).thenAnswer((_) async => '2');

        // Should work with inherited methods
        final object = await view.getObject();
        expect(object, isNotNull);
        expect(object!.title, equals('Another Post'));

        // Should work with inherited context object name method
        expect(view.getContextObjectName(), equals('post'));
      });

      test('should override context building appropriately', () async {
        final view = RichContextTemplateDetailView();
        view.setAdapter(mockAdapter);
        when(mockAdapter.getParam('id')).thenAnswer((_) async => '1');
        final context = await view.getContextData();
        expect(context['post'], isA<Post>());
        expect(context['site_name'], equals('My Blog'));
        expect(context['related_posts'], isA<List>());
      });
    });
  });
}
