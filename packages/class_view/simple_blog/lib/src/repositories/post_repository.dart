import 'package:drift/drift.dart';

import '../database/database.dart';
import '../models/post.dart';

/// Repository for posts using Drift database
class PostRepository {
  final BlogDatabase database;

  PostRepository(this.database);

  /// Convert BlogPost to Post domain model
  Post _fromBlogPost(BlogPost blogPost) {
    return Post(
      id: blogPost.id.toString(),
      title: blogPost.title,
      content: blogPost.content,
      author: blogPost.author,
      slug: blogPost.slug,
      isPublished: blogPost.isPublished,
      tags:
          blogPost.tags
              ?.split(',')
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          [],
      createdAt: blogPost.createdAt,
      updatedAt: blogPost.updatedAt,
    );
  }

  /// Convert Post domain model to PostsCompanion
  PostsCompanion _toCompanion(Post post) {
    return PostsCompanion(
      title: Value(post.title),
      content: Value(post.content),
      author: Value(post.author),
      slug: Value(post.slug),
      isPublished: Value(post.isPublished),
      tags: Value(post.tags.join(',')),
      updatedAt: Value(DateTime.now()),
    );
  }

  /// Find all posts
  Future<List<Post>> findAll({bool publishedOnly = false}) async {
    final blogPosts = await database.getAllPosts(publishedOnly: publishedOnly);
    return blogPosts.map(_fromBlogPost).toList();
  }

  /// Find post by ID
  Future<Post?> findById(String id) async {
    final postId = int.tryParse(id);
    if (postId == null) return null;

    final blogPost = await database.getPostById(postId);
    return blogPost != null ? _fromBlogPost(blogPost) : null;
  }

  /// Find post by slug
  Future<Post?> findBySlug(String slug) async {
    final blogPost = await database.getPostBySlug(slug);
    return blogPost != null ? _fromBlogPost(blogPost) : null;
  }

  /// Create a new post
  Future<Post> create(Post post) async {
    final companion = PostsCompanion.insert(
      title: post.title,
      content: post.content,
      author: post.author,
      slug: post.slug,
      isPublished: Value(post.isPublished),
      tags: Value(post.tags.join(',')),
    );

    final id = await database.createPost(companion);
    final createdPost = await database.getPostById(id);
    return _fromBlogPost(createdPost!);
  }

  /// Update an existing post
  Future<Post> update(Post post) async {
    final postId = int.tryParse(post.id);
    if (postId == null) {
      throw ArgumentError('Invalid post ID: ${post.id}');
    }

    final companion = _toCompanion(post);
    final updated = await database.updatePost(postId, companion);

    if (!updated) {
      throw ArgumentError('Post with id ${post.id} not found');
    }

    final updatedPost = await database.getPostById(postId);
    return _fromBlogPost(updatedPost!);
  }

  /// Delete a post
  Future<void> delete(String id) async {
    final postId = int.tryParse(id);
    if (postId == null) {
      throw ArgumentError('Invalid post ID: $id');
    }

    final deletedCount = await database.deletePost(postId);
    if (deletedCount == 0) {
      throw ArgumentError('Post with id $id not found');
    }
  }

  /// Search posts
  Future<List<Post>> search(String query, {bool publishedOnly = false}) async {
    final blogPosts = await database.searchPosts(
      query,
      publishedOnly: publishedOnly,
    );
    return blogPosts.map(_fromBlogPost).toList();
  }

  /// Get posts with pagination
  Future<({List<Post> items, int total})> findWithPagination({
    int page = 1,
    int pageSize = 10,
    bool publishedOnly = false,
    String? search,
  }) async {
    final result = await database.getPaginatedPosts(
      page: page,
      pageSize: pageSize,
      publishedOnly: publishedOnly,
      search: search,
    );

    return (
      items: result.items.map(_fromBlogPost).toList(),
      total: result.total,
    );
  }

  /// Clear all posts (useful for testing)
  Future<void> clear() async {
    // Note: This would require additional implementation in the database
    // For now, we'll leave this as a placeholder
  }

  /// Get total count
  Future<int> get count async {
    final posts = await findAll();
    return posts.length;
  }
}

/// Extension to add firstOrNull method for older Dart versions
extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
