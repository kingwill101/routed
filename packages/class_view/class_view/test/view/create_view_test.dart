import 'package:class_view/class_view.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../shared/mock_adapter.mocks.dart';

// Test model (reusing from detail_view_test)
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

/// Test CreateView implementation
class TestPostCreateView extends CreateView<Post> {
  static int _nextId = 1;
  final List<Post> _posts = [];

  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    final post = Post(
      id: _nextId++,
      title: (data['title'] as String?) ?? 'Default Title',
      content: (data['content'] as String?) ?? 'Default Content',
      createdAt: DateTime.now(),
    );
    _posts.add(post);
    return post;
  }

  List<Post> get createdPosts => List.unmodifiable(_posts);
}

/// Test CreateView with validation
class ValidatingPostCreateView extends CreateView<Post> {
  static int _nextId = 100;
  final List<Post> _posts = [];

  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    // Validate required fields
    if (data['title'] == null || (data['title'] as String).isEmpty) {
      throw ValidationException('Title is required');
    }
    if (data['content'] == null || (data['content'] as String).isEmpty) {
      throw ValidationException('Content is required');
    }

    final post = Post(
      id: _nextId++,
      title: data['title'] as String,
      content: data['content'] as String,
      createdAt: DateTime.now(),
    );
    _posts.add(post);
    return post;
  }

  List<Post> get createdPosts => List.unmodifiable(_posts);
}

/// Test CreateView with custom success URL
class CustomSuccessCreateView extends CreateView<Post>
    with SuccessFailureUrlMixin {
  static int _nextId = 200;

  @override
  String get successUrl => '/posts/success';

  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    return Post(
      id: _nextId++,
      title: data['title'] as String,
      content: data['content'] as String,
      createdAt: DateTime.now(),
    );
  }
}

/// Test CreateView that throws database error
class ErrorCreateView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    throw Exception('Database connection failed');
  }
}

class ValidationException implements Exception {
  final String message;

  ValidationException(this.message);

  @override
  String toString() => 'ValidationException: $message';
}

void main() {
  group('CreateView Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
    });

    group('Basic Functionality', () {
      test('should have GET and POST as allowed methods', () {
        final view = TestPostCreateView();
        expect(view.allowedMethods, containsAll(['GET', 'POST']));
        expect(view.allowedMethods.length, equals(2));
      });
    });

    group('GET Request Handling', () {
      test('should handle GET request for form display', () async {
        final view = TestPostCreateView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should return form data for display
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('POST Request Handling', () {
      late MockViewAdapter mockAdapter;
      late TestPostCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = TestPostCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should create object from POST data', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should create object and return JSON
        expect(view.createdPosts.length, equals(1));
        expect(view.createdPosts.first.title, equals('New Post'));
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should handle successful creation with JSON response', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should create object and return JSON
        expect(view.createdPosts.length, equals(1));
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should handle form data input', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/x-www-form-urlencoded');
        when(mockAdapter.getFormData()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );
        when(
          mockAdapter.redirect(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should create object from form data
        expect(view.createdPosts.length, equals(1));
        expect(view.createdPosts.first.title, equals('New Post'));
      });
    });

    group('Validation Handling', () {
      late MockViewAdapter mockAdapter;
      late ValidatingPostCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = ValidatingPostCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should handle validation errors', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {
            'content': 'Test content', // Missing required title
          },
        );
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should have called onFailure which sends error response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);

        // Object should not have been created
        expect(view.createdPosts.length, equals(0));
      });

      test('should pass validation with valid data', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );

        await view.dispatch();

        // Object should have been created
        expect(view.createdPosts.length, equals(1));
        expect(view.createdPosts.first.title, equals('New Post'));
      });
    });

    group('Success/Failure Handling', () {
      late MockViewAdapter mockAdapter;
      late CustomSuccessCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = CustomSuccessCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should handle custom success URL', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );
        when(
          mockAdapter.redirect(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should redirect to success URL (implementation depends on SuccessUrlMixin)
        verify(
          mockAdapter.redirect(
            '/posts/success',
            statusCode: anyNamed('statusCode'),
          ),
        ).called(1);
      });

      test('should handle database errors', () async {
        final errorView = ErrorCreateView();
        errorView.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getHeader('content-type'),
        ).thenAnswer((_) async => 'application/json');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await errorView.dispatch();

        // Should have sent error response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Method Restrictions', () {
      late MockViewAdapter mockAdapter;
      late TestPostCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = TestPostCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should reject PUT requests', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PUT');
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should send method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject DELETE requests', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'DELETE');
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should send method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Context Building', () {
      test('should build context for GET request', () async {
        final view = TestPostCreateView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        // Should contain base context from ContextMixin
        expect(context, isA<Map<String, dynamic>>());
      });
    });

    group('Data Handling', () {
      late MockViewAdapter mockAdapter;
      late TestPostCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = TestPostCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should handle empty JSON body', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(mockAdapter.getJsonBody()).thenAnswer((_) async => {});
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should handle empty data gracefully (might create with defaults or fail)
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should handle malformed JSON', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(
          mockAdapter.getJsonBody(),
        ).thenThrow(FormatException('Invalid JSON'));
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should handle JSON parsing error
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should handle missing required fields', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {
            'content': 'Test content', // Missing required title
          },
        );
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Should handle missing fields (behavior depends on implementation)
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Concurrent Operations', () {
      late MockViewAdapter mockAdapter;
      late TestPostCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = TestPostCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should handle concurrent creation requests', () async {
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');
        when(mockAdapter.getJsonBody()).thenAnswer(
          (_) async => {'title': 'New Post', 'content': 'Test content'},
        );

        // Define postData for concurrent operations
        final postData = {'title': 'New Post', 'content': 'Test content'};

        // Simulate multiple concurrent POST requests
        final futures = List.generate(3, (_) => view.performCreate(postData));
        final results = await Future.wait(futures);

        // Should create multiple objects
        expect(results.length, equals(3));
        for (final post in results) {
          expect(post.title, equals('New Post'));
        }
      });
    });

    group('Integration Tests', () {
      late MockViewAdapter mockAdapter;
      late TestPostCreateView view;

      setUp(() {
        mockAdapter = MockViewAdapter();
        view = TestPostCreateView();
        view.setAdapter(mockAdapter);
      });

      test('should work with form processing mixin', () async {
        // This would test integration with FormProcessingMixin if available
        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).thenAnswer((_) async {});

        await view.dispatch();

        // Basic functionality should work
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });
  });
}
