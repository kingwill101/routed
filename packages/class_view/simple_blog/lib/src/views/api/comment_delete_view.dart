import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../models/comment.dart';
import '../../repositories/comment_repository.dart';

/// API view for deleting comments
///
/// Demonstrates:
/// - DeleteView with cascading considerations
/// - Authorization checks (placeholder)
/// - Soft vs hard delete patterns
class CommentDeleteView extends DeleteView<Comment> {
  late final CommentRepository _repository;

  CommentDeleteView() {
    _repository = CommentRepository(DatabaseService.instance);
  }

  @override
  Future<Comment?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await _repository.findById(id);
  }

  @override
  Future<void> performDelete(Comment object) async {
    // TODO: Add permission check here
    // if (!currentUser.canDelete(comment)) {
    //   throw HttpException.forbidden('You cannot delete this comment');
    // }

    await _repository.delete(object.id);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final comment = object as Comment?;

    sendJson({
      'success': true,
      'message': 'Comment deleted successfully.',
      'deleted_comment_id': comment?.id,
    }, statusCode: 200);
  }

  @override
  Future<void> onFailure(Object error, [dynamic object]) async {
    int statusCode = 500;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    }

    sendJson({'error': message, 'success': false}, statusCode: statusCode);
  }

  @override
  String get successUrl => '/api/comments';
}
