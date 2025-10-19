import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../models/comment.dart';
import '../../repositories/comment_repository.dart';
import '../../repositories/post_repository.dart';

/// API view for listing comments, optionally filtered by post
///
/// Demonstrates:
/// - ListView with optional filtering
/// - Parent-child resource listing
/// - Pagination for nested resources
/// - Query parameter handling
class CommentListView extends ListView<Comment> {
  late final CommentRepository _commentRepo;
  late final PostRepository _postRepo;

  CommentListView() {
    _commentRepo = CommentRepository(DatabaseService.instance);
    _postRepo = PostRepository(DatabaseService.instance);
  }

  @override
  int get paginate => 20; // Show 20 comments per page

  @override
  Future<({List<Comment> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    // Check if filtering by post
    final postId = await getParam('postId');

    if (postId != null && postId.isNotEmpty) {
      // Validate post exists
      final post = await _postRepo.findById(postId);
      if (post == null) {
        throw HttpException.notFound('Post not found');
      }

      // Return comments for specific post
      return await _commentRepo.findByPostIdPaginated(
        postId: postId,
        page: page,
        pageSize: pageSize,
      );
    }

    // Return all recent comments (admin view)
    final comments = await _commentRepo.findRecent(limit: 100);
    return (items: comments, total: comments.length);
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final context = await super.getExtraContext();

    // Add post info if filtering
    final postId = await getParam('postId');
    if (postId != null && postId.isNotEmpty) {
      final post = await _postRepo.findById(postId);
      if (post != null) {
        context['post'] = post.toJson();
        context['post_title'] = post.title;
      }
    }

    return context;
  }
}
