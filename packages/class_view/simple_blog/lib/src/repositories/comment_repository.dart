import 'package:drift/drift.dart';

import '../database/database.dart';
import '../models/comment.dart';

/// Repository for managing blog comments with Drift database
class CommentRepository {
  final BlogDatabase database;

  CommentRepository(this.database);

  /// Convert BlogComment to Comment domain model
  Comment _fromBlogComment(BlogComment blogComment) {
    return Comment(
      id: blogComment.id.toString(),
      content: blogComment.content,
      author: blogComment.author,
      postId: blogComment.postId.toString(),
      createdAt: blogComment.createdAt,
    );
  }

  /// Create a new comment
  Future<Comment> create(Comment comment) async {
    final id = await database
        .into(database.comments)
        .insert(
          CommentsCompanion.insert(
            content: comment.content,
            author: comment.author,
            postId: int.parse(comment.postId),
          ),
        );

    return comment.copyWith(id: id.toString());
  }

  /// Find all comments for a specific post
  Future<List<Comment>> findByPostId(String postId) async {
    final query = database.select(database.comments)
      ..where((c) => c.postId.equals(int.parse(postId)))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);

    final results = await query.get();
    return results.map(_fromBlogComment).toList();
  }

  /// Find a comment by ID
  Future<Comment?> findById(String id) async {
    final query = database.select(database.comments)
      ..where((c) => c.id.equals(int.parse(id)));

    final results = await query.get();
    if (results.isEmpty) return null;
    return _fromBlogComment(results.first);
  }

  /// Get paginated comments for a post
  Future<({List<Comment> items, int total})> findByPostIdPaginated({
    required String postId,
    int page = 1,
    int pageSize = 10,
  }) async {
    final offset = (page - 1) * pageSize;

    // Get total count
    final countQuery = database.selectOnly(database.comments)
      ..where(database.comments.postId.equals(int.parse(postId)))
      ..addColumns([database.comments.id.count()]);

    final countResult = await countQuery.getSingle();
    final total = countResult.read(database.comments.id.count()) ?? 0;

    // Get paginated results
    final query = database.select(database.comments)
      ..where((c) => c.postId.equals(int.parse(postId)))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)])
      ..limit(pageSize, offset: offset);

    final results = await query.get();
    return (items: results.map(_fromBlogComment).toList(), total: total);
  }

  /// Delete a comment
  Future<void> delete(String id) async {
    await (database.delete(
      database.comments,
    )..where((c) => c.id.equals(int.parse(id)))).go();
  }

  /// Delete all comments for a post (cascade)
  Future<void> deleteByPostId(String postId) async {
    await (database.delete(
      database.comments,
    )..where((c) => c.postId.equals(int.parse(postId)))).go();
  }

  /// Get comment count for a post
  Future<int> countByPostId(String postId) async {
    final countQuery = database.selectOnly(database.comments)
      ..where(database.comments.postId.equals(int.parse(postId)))
      ..addColumns([database.comments.id.count()]);

    final result = await countQuery.getSingle();
    return result.read(database.comments.id.count()) ?? 0;
  }

  /// Get recent comments across all posts
  Future<List<Comment>> findRecent({int limit = 5}) async {
    final query = database.select(database.comments)
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)])
      ..limit(limit);

    final results = await query.get();
    return results.map(_fromBlogComment).toList();
  }
}
