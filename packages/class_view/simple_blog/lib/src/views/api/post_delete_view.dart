import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

/// Delete view for removing blog posts
class PostDeleteView extends DeleteView<Post> {
  late final PostRepository _repository;

  PostDeleteView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  String get successUrl => '/posts';

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;

    return await _repository.findById(id);
  }

  @override
  Future<void> performDelete(Post object) async {
    await _repository.delete(object.id);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final post = object as Post?;

    sendJson({
      'success': true,
      'message': 'Post "${post?.title}" has been deleted successfully.',
      'redirect_url': successUrl,
    }, statusCode: 200);
  }

  @override
  Future<void> onFailure(Object error, [dynamic object]) async {
    int statusCode = 500;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    } else if (error is ArgumentError) {
      statusCode = 404;
      message = error.message;
    } else {
      message = 'An unexpected error occurred while deleting the post';
    }

    sendJson({'error': message, 'success': false}, statusCode: statusCode);
  }

  Future<void> onObjectNotFound() async {
    sendJson({
      'error': 'Post not found',
      'message': 'The post you are trying to delete could not be found.',
    }, statusCode: 404);
  }

  @override
  Future<void> get() async {
    final post = await getObject();
    if (post == null) {
      await onObjectNotFound();
      return;
    }

    // Return confirmation page data
    final requestUri = await getUri();
    await sendJson({
      'message': 'Confirm post deletion',
      'post': post.toJson(),
      'warning': 'This action cannot be undone.',
      'form_action': requestUri.path,
      'form_method': 'DELETE',
      'cancel_url': '/posts/${post.slug}',
    });
  }
}
