import 'package:simple_blog/simple_blog.dart';
import 'package:test/test.dart';

void main() {
  group('PostRepository Tests', () {
    late PostRepository repository;
    late BlogDatabase database;

    setUp(() async {
      // Create in-memory database for testing
      database = BlogDatabase(inMemory: true);
      repository = PostRepository(database);

      // Wait for database to initialize
      await database.customStatement('SELECT 1');

      // Clear any existing data
      await database.delete(database.posts).go();
      await database.delete(database.comments).go();
    });

    tearDown(() async {
      await database.close();
    });

    test('should create and retrieve a post', () async {
      // Create a test post
      final post = Post.create(
        title: 'Test Post',
        content: 'This is a test post content',
        author: 'Test Author',
        isPublished: true,
        tags: ['test', 'dart'],
      );

      // Create the post
      final createdPost = await repository.create(post);

      // Verify creation
      expect(createdPost.title, equals('Test Post'));
      expect(createdPost.author, equals('Test Author'));
      expect(createdPost.isPublished, isTrue);
      expect(createdPost.tags, equals(['test', 'dart']));

      // Retrieve by ID
      final retrievedPost = await repository.findById(createdPost.id);
      expect(retrievedPost, isNotNull);
      expect(retrievedPost!.title, equals('Test Post'));
    });

    test('should find post by slug', () async {
      final post = Post.create(
        title: 'Unique Title for Slug Test',
        content: 'Content',
        author: 'Author',
        slug: 'unique-slug-test',
      );

      await repository.create(post);

      final foundPost = await repository.findBySlug('unique-slug-test');
      expect(foundPost, isNotNull);
      expect(foundPost!.title, equals('Unique Title for Slug Test'));
    });

    test('should update an existing post', () async {
      // Create initial post
      final post = Post.create(
        title: 'Original Title',
        content: 'Original content',
        author: 'Author',
      );

      final createdPost = await repository.create(post);

      // Update the post
      final updatedPost = createdPost.copyWith(
        title: 'Updated Title',
        content: 'Updated content',
        isPublished: true,
      );

      final result = await repository.update(updatedPost);

      expect(result.title, equals('Updated Title'));
      expect(result.content, equals('Updated content'));
      expect(result.isPublished, isTrue);
      expect(result.id, equals(createdPost.id));
    });

    test('should delete a post', () async {
      // Create a post
      final post = Post.create(
        title: 'Post to Delete',
        content: 'This will be deleted',
        author: 'Author',
      );

      final createdPost = await repository.create(post);

      // Verify it exists
      final foundPost = await repository.findById(createdPost.id);
      expect(foundPost, isNotNull);

      // Delete it
      await repository.delete(createdPost.id);

      // Verify it's gone
      final deletedPost = await repository.findById(createdPost.id);
      expect(deletedPost, isNull);
    });

    test('should search posts by content', () async {
      // Create test posts
      await repository.create(
        Post.create(
          title: 'Flutter Development',
          content: 'Learning Flutter framework',
          author: 'Dev1',
          tags: ['flutter', 'mobile'],
        ),
      );

      await repository.create(
        Post.create(
          title: 'Dart Programming',
          content: 'Understanding Dart language',
          author: 'Dev2',
          tags: ['dart', 'programming'],
        ),
      );

      await repository.create(
        Post.create(
          title: 'Web Development',
          content: 'Building web applications',
          author: 'Dev3',
          tags: ['web', 'frontend'],
        ),
      );

      // Search for Flutter
      final flutterPosts = await repository.search('Flutter');
      expect(flutterPosts.length, equals(1));
      expect(flutterPosts.first.title, equals('Flutter Development'));

      // Search for development (should find multiple)
      final devPosts = await repository.search('Development');
      expect(devPosts.length, greaterThanOrEqualTo(2));
    });

    test('should handle pagination correctly', () async {
      // Create multiple posts
      for (int i = 1; i <= 7; i++) {
        await repository.create(
          Post.create(
            title: 'Post $i',
            content: 'Content for post $i',
            author: 'Author $i',
            isPublished: true,
          ),
        );
      }

      // Test pagination
      final page1 = await repository.findWithPagination(
        page: 1,
        pageSize: 3,
        publishedOnly: true,
      );

      expect(page1.items.length, equals(3));
      expect(page1.total, equals(7));

      final page2 = await repository.findWithPagination(
        page: 2,
        pageSize: 3,
        publishedOnly: true,
      );

      expect(page2.items.length, equals(3));
      expect(page2.total, equals(7));

      final page3 = await repository.findWithPagination(
        page: 3,
        pageSize: 3,
        publishedOnly: true,
      );

      expect(page3.items.length, equals(1)); // Last page
      expect(page3.total, equals(7));
    });

    test('should filter published posts only', () async {
      // Create published and unpublished posts
      await repository.create(
        Post.create(
          title: 'Published Post',
          content: 'This is published',
          author: 'Author',
          isPublished: true,
        ),
      );

      await repository.create(
        Post.create(
          title: 'Draft Post',
          content: 'This is a draft',
          author: 'Author',
          isPublished: false,
        ),
      );

      // Get all posts
      final allPosts = await repository.findAll();
      expect(allPosts.length, equals(2));

      // Get only published posts
      final publishedPosts = await repository.findAll(publishedOnly: true);
      expect(publishedPosts.length, equals(1));
      expect(publishedPosts.first.title, equals('Published Post'));
    });

    test('should handle search with pagination', () async {
      // Create posts with specific content
      for (int i = 1; i <= 5; i++) {
        await repository.create(
          Post.create(
            title: 'Testing Post $i',
            content: 'Content about testing functionality $i',
            author: 'Tester',
            isPublished: true,
          ),
        );
      }

      await repository.create(
        Post.create(
          title: 'Different Topic',
          content: 'This is about something else',
          author: 'Author',
          isPublished: true,
        ),
      );

      // Search with pagination
      final result = await repository.findWithPagination(
        page: 1,
        pageSize: 3,
        search: 'testing',
        publishedOnly: true,
      );

      expect(result.items.length, equals(3));
      expect(result.total, equals(5)); // Only testing posts
      expect(result.items.every((p) => p.title.contains('Testing')), isTrue);
    });

    test('should handle tags correctly', () async {
      final post = Post.create(
        title: 'Tagged Post',
        content: 'Post with multiple tags',
        author: 'Author',
        tags: ['dart', 'flutter', 'testing', 'web'],
      );

      final createdPost = await repository.create(post);
      final retrievedPost = await repository.findById(createdPost.id);

      expect(
        retrievedPost!.tags,
        equals(['dart', 'flutter', 'testing', 'web']),
      );
    });

    test('should generate unique slugs with timestamps', () async {
      final post1 = Post.create(
        title: 'Test Post',
        content: 'First post',
        author: 'Author',
      );

      final post2 = Post.create(
        title: 'Test Post',
        content: 'Second post with same title',
        author: 'Author',
      );

      final created1 = await repository.create(post1);
      final created2 = await repository.create(post2);

      // Should have different slugs even with same title (timestamp makes them unique)
      expect(created1.slug, isNot(equals(created2.slug)));
      expect(created1.slug, startsWith('test-post-'));
      expect(created2.slug, startsWith('test-post-'));
    });
  });
}
