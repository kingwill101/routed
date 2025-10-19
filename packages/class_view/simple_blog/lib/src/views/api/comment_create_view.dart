import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../models/comment.dart';
import '../../repositories/comment_repository.dart';
import '../../repositories/post_repository.dart';

/// API view for creating comments on blog posts
///
/// Demonstrates:
/// - Nested resource creation (comments belong to posts)
/// - Parent validation (ensure post exists)
/// - Custom error handling for nested resources
/// - Clean JSON API responses
class CommentCreateView extends CreateView<Comment> {
  late final CommentRepository _commentRepo;
  late final PostRepository _postRepo;

  CommentCreateView() {
    _commentRepo = CommentRepository(DatabaseService.instance);
    _postRepo = PostRepository(DatabaseService.instance);
  }

  @override
  Future<Comment> performCreate(Map<String, dynamic> data) async {
    // Validate post exists
    final postId = data['postId'] as String?;
    if (postId == null || postId.isEmpty) {
      throw ArgumentError('Post ID is required');
    }

    final post = await _postRepo.findById(postId);
    if (post == null) {
      throw HttpException.notFound('Post not found');
    }

    // Validate comment content
    final content = data['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw ArgumentError('Comment content is required');
    }

    if (content.length > 1000) {
      throw ArgumentError('Comment must be 1000 characters or less');
    }

    // Validate author
    final author = data['author'] as String?;
    if (author == null || author.trim().isEmpty) {
      throw ArgumentError('Author name is required');
    }

    // Create comment
    final comment = Comment.fromFormData(data);
    return await _commentRepo.create(comment);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final comment = object as Comment;

    sendJson({
      'success': true,
      'comment': comment.toJson(),
      'message': 'Comment posted successfully!',
    }, statusCode: 201);
  }

  @override
  Future<void> onFailure(Object error, [dynamic object]) async {
    int statusCode = 400;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    } else if (error is ArgumentError) {
      statusCode = 400;
      message = error.message;
    } else {
      statusCode = 500;
      message = 'An unexpected error occurred while posting your comment';
    }

    sendJson({
      'error': message,
      'success': false,
      'form_data': object,
    }, statusCode: statusCode);
  }

  @override
  String get successUrl => '/posts'; // Default, overridden in onSuccess
}
