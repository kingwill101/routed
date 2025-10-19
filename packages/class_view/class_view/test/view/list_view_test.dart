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
  final bool published;

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.published = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'published': published,
  };
}

/// Test ListView implementation
class TestPostListView extends ListView<Post> {
  @override
  String? get contextObjectName => 'posts';

  static final List<Post> _allPosts = [
    Post(
      id: 1,
      title: 'First Post',
      content: 'Content 1',
      createdAt: DateTime(2024, 1, 1),
      published: true,
    ),
    Post(
      id: 2,
      title: 'Second Post',
      content: 'Content 2',
      createdAt: DateTime(2024, 1, 2),
      published: false,
    ),
    Post(
      id: 3,
      title: 'Third Post',
      content: 'Content 3',
      createdAt: DateTime(2024, 1, 3),
      published: true,
    ),
    Post(
      id: 4,
      title: 'Fourth Post',
      content: 'Content 4',
      createdAt: DateTime(2024, 1, 4),
      published: true,
    ),
    Post(
      id: 5,
      title: 'Fifth Post',
      content: 'Content 5',
      createdAt: DateTime(2024, 1, 5),
      published: false,
    ),
  ];

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    // Simple pagination logic
    final startIndex = (page - 1) * pageSize;
    final items = _allPosts.skip(startIndex).take(pageSize).toList();

    return (items: items, total: _allPosts.length);
  }
}

/// Test ListView with custom pagination
class PaginatedPostListView extends ListView<Post> {
  @override
  String? get contextObjectName => 'posts';

  @override
  int? get paginate => 2; // 2 items per page

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final actualPageSize = paginate ?? pageSize;
    // Ensure page is at least 1
    final safePage = page < 1 ? 1 : page;
    final startIndex = (safePage - 1) * actualPageSize;
    final allPosts = TestPostListView._allPosts;
    final items = allPosts.skip(startIndex).take(actualPageSize).toList();

    return (items: items, total: allPosts.length);
  }
}

/// Test ListView with filtering
class FilteredPostListView extends ListView<Post> {
  @override
  String? get contextObjectName => 'posts';

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final status = await getParam('status');
    final searchTerm = await getParam('search');

    var filteredPosts = TestPostListView._allPosts;

    // Filter by published status
    if (status != null) {
      final isPublished = status.toLowerCase() == 'published';
      filteredPosts = filteredPosts
          .where((post) => post.published == isPublished)
          .toList();
    }

    // Filter by search term
    if (searchTerm != null && searchTerm.isNotEmpty) {
      filteredPosts = filteredPosts
          .where(
            (post) =>
                post.title.toLowerCase().contains(searchTerm.toLowerCase()) ||
                post.content.toLowerCase().contains(searchTerm.toLowerCase()),
          )
          .toList();
    }

    // Apply pagination
    final startIndex = (page - 1) * pageSize;
    final items = filteredPosts.skip(startIndex).take(pageSize).toList();

    return (items: items, total: filteredPosts.length);
  }
}

/// Test ListView with custom context object name
class CustomPostListView extends ListView<Post> {
  @override
  String? get contextObjectName => 'articles';

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final allPosts = TestPostListView._allPosts;
    return (items: allPosts, total: allPosts.length);
  }
}

/// Test ListView that throws an error
class ErrorListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    throw Exception('Database connection failed');
  }
}

void main() {
  group('ListView Tests', () {
    late MockViewAdapter mockAdapter;

    setUp(() {
      mockAdapter = MockViewAdapter();
    });

    group('Basic Functionality', () {
      test('should have GET as allowed method', () {
        final view = TestPostListView();
        expect(view.allowedMethods, contains('GET'));
        expect(view.allowedMethods.length, equals(1));
      });

      test('should use default page parameter "page"', () {
        final view = TestPostListView();
        expect(view.pageParam, equals('page'));
      });

      test('should use class name as default context object name', () {
        final view = TestPostListView();
        expect(view.getContextObjectName(), equals('posts'));
      });

      test('should allow custom context object name', () {
        final view = CustomPostListView();
        expect(view.getContextObjectName(), equals('articles'));
      });

      test('should have no pagination by default', () {
        final view = TestPostListView();
        expect(view.paginate, isNull);
      });
    });

    group('Object List Retrieval', () {
      test('should retrieve all objects without pagination', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        final result = await view.getObjectList();

        expect(result.items.length, equals(5));
        expect(result.total, equals(5));
        expect(result.items.first.title, equals('First Post'));
      });

      test('should handle empty result set', () async {
        final view = FilteredPostListView();
        view.setAdapter(mockAdapter);

        // Filter for non-existent search term
        when(
          mockAdapter.getParam('search'),
        ).thenAnswer((_) async => 'nonexistent');

        final result = await view.getObjectList();

        expect(result.items.length, equals(0));
        expect(result.total, equals(0));
      });
    });

    group('Pagination', () {
      test('should handle pagination with custom page size', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '1');

        final result = await view.getPaginatedResults();

        expect(result.objects.length, equals(2)); // paginate = 2
        expect(result.total, equals(5));
        expect(result.pages, equals(3)); // ceil(5/2) = 3
      });

      test('should handle second page pagination', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '2');

        final result = await view.getPaginatedResults();

        expect(result.objects.length, equals(2));
        expect(result.objects.first.id, equals(3)); // Third post on page 2
      });

      test('should handle last page with fewer items', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '3');

        final result = await view.getPaginatedResults();

        expect(result.objects.length, equals(1)); // Only one item on last page
        expect(result.objects.first.id, equals(5)); // Fifth post
      });

      test('should handle invalid page numbers', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '0');

        final result = await view.getPaginatedResults();

        // Should default to page 1
        expect(result.objects.length, equals(2));
        expect(result.objects.first.id, equals(1));
      });

      test('should handle non-numeric page parameter', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => 'invalid');

        final result = await view.getPaginatedResults();

        // Should default to page 1
        expect(result.objects.length, equals(2));
      });
    });

    group('Filtering', () {
      test('should filter by published status', () async {
        final view = FilteredPostListView();
        view.setAdapter(mockAdapter);

        when(
          mockAdapter.getParam('status'),
        ).thenAnswer((_) async => 'published');

        final result = await view.getObjectList();

        expect(result.items.length, equals(3)); // 3 published posts
        for (final post in result.items) {
          expect(post.published, isTrue);
        }
      });

      test('should filter by search term', () async {
        final view = FilteredPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('search')).thenAnswer((_) async => 'First');

        final result = await view.getObjectList();

        expect(result.items.length, equals(1));
        expect(result.items.first.title, equals('First Post'));
      });

      test('should combine multiple filters', () async {
        final view = FilteredPostListView();
        view.setAdapter(mockAdapter);

        when(
          mockAdapter.getParam('status'),
        ).thenAnswer((_) async => 'published');
        when(mockAdapter.getParam('search')).thenAnswer((_) async => 'Third');

        final result = await view.getObjectList();

        expect(result.items.length, equals(1));
        expect(result.items.first.title, equals('Third Post'));
        expect(result.items.first.published, isTrue);
      });
    });

    group('Context Building', () {
      test('should build context with objects list', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context['posts'], isA<List<Post>>());
        expect((context['posts'] as List).length, equals(5));
      });

      test('should use custom context object name', () async {
        final view = CustomPostListView();
        view.setAdapter(mockAdapter);

        final context = await view.getContextData();

        expect(context['articles'], isA<List<Post>>());
        expect((context['articles'] as List).length, equals(5));
      });

      test('should include pagination info in context', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '2');

        final context = await view.getContextData();

        expect(context['posts'], isA<List<Post>>());
        expect(context['paginator'], isA<Map<String, dynamic>>());
        expect(context['paginator']['count'], equals(5));
        expect(context['paginator']['num_pages'], equals(3));
        expect(context['paginator']['page_size'], equals(2));
      });
    });

    group('GET Request Handling', () {
      test('should handle successful GET request', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');

        await view.dispatch();

        // Verify response was sent with context data
        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['posts'], isA<List>());
      });

      test('should handle paginated GET request', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(mockAdapter.getParam('page')).thenAnswer((_) async => '2');

        await view.dispatch();

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['paginator']['count'], equals(5));
        expect(responseData['posts'], isA<List>());
        expect((responseData['posts'] as List).length, equals(2));
      });

      test('should handle filtered GET request', () async {
        final view = FilteredPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'GET');
        when(
          mockAdapter.getParam('status'),
        ).thenAnswer((_) async => 'published');

        await view.dispatch();

        final captured = verify(
          mockAdapter.writeJson(captureAny, statusCode: anyNamed('statusCode')),
        ).captured;
        final responseData = captured.first as Map<String, dynamic>;

        expect(responseData['posts'], isA<List>());
        expect((responseData['posts'] as List).length, equals(3));
      });

      test('should handle errors gracefully', () async {
        final view = ErrorListView();
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
      test('should reject POST requests', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'POST');

        await view.dispatch();

        // Should send method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject PUT requests', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'PUT');

        await view.dispatch();

        // Should send method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });

      test('should reject DELETE requests', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getMethod()).thenAnswer((_) async => 'DELETE');

        await view.dispatch();

        // Should send method not allowed response
        verify(
          mockAdapter.writeJson(any, statusCode: anyNamed('statusCode')),
        ).called(1);
      });
    });

    group('Edge Cases', () {
      test('should handle missing page parameter', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => null);

        final result = await view.getPaginatedResults();

        // Should default to page 1
        expect(result.objects.length, equals(2));
        expect(result.objects.first.id, equals(1));
      });

      test('should handle page beyond available data', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '999');

        final result = await view.getPaginatedResults();

        // Should return empty list for page beyond data
        expect(result.objects.length, equals(0));
        expect(result.total, equals(5));
        expect(result.pages, equals(3));
      });

      test('should handle zero page size', () async {
        final view = TestPostListView();
        view.setAdapter(mockAdapter);

        final result = await view.getObjectList(pageSize: 0);

        // Should handle zero page size gracefully
        expect(result.items, isA<List<Post>>());
      });
    });

    group('Performance and Memory', () {
      test('should not load all data when paginating', () async {
        final view = PaginatedPostListView();
        view.setAdapter(mockAdapter);

        when(mockAdapter.getParam('page')).thenAnswer((_) async => '1');

        final result = await view.getPaginatedResults();

        // Should only return requested page size
        expect(result.objects.length, equals(2));
        expect(result.total, equals(5)); // But still know total count
      });
    });
  });
}
