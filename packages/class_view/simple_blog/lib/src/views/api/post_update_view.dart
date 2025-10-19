import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

/// Update view for editing existing blog posts
class PostUpdateView extends UpdateView<Post> {
  late final PostRepository _repository;

  PostUpdateView() {
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
  Future<Post> performUpdate(Post object, Map<String, dynamic> data) async {
    // Validate required fields
    final title = data['title'] as String?;
    if (title == null || title.trim().isEmpty) {
      throw ArgumentError('Title is required and cannot be empty');
    }

    final content = data['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw ArgumentError('Content is required and cannot be empty');
    }

    final author = data['author'] as String?;
    if (author == null || author.trim().isEmpty) {
      throw ArgumentError('Author is required and cannot be empty');
    }

    // Validate title length
    if (title.length > 200) {
      throw ArgumentError('Title cannot be longer than 200 characters');
    }

    // Parse tags
    final tags = data['tags'] is String
        ? (data['tags'] as String)
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : data['tags'] as List<String>? ?? [];

    // Update the post
    final updatedPost = object.copyWith(
      title: title,
      content: content,
      author: author,
      slug: data['slug'] as String?,
      isPublished: data['isPublished'] as bool? ?? object.isPublished,
      tags: tags,
    );

    return await _repository.update(updatedPost);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final post = object as Post;

    sendJson({
      'success': true,
      'post': post.toJson(),
      'redirect_url': '/posts/${post.slug}',
      'message': 'Post updated successfully!',
    }, statusCode: 200);
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
      message = 'An unexpected error occurred while updating the post';
    }

    sendJson({
      'error': message,
      'success': false,
      'form_data': object,
    }, statusCode: statusCode);
  }

  Future<void> onObjectNotFound() async {
    sendJson({
      'error': 'Post not found',
      'message': 'The post you are trying to edit could not be found.',
    }, statusCode: 404);
  }

  @override
  Future<void> get() async {
    final post = await getObject();
    if (post == null) {
      await onObjectNotFound();
      return;
    }

    // Return current post data for editing
    final requestUri = await getUri();
    await sendJson({
      'message': 'Edit blog post',
      'form_action': requestUri.path,
      'form_method': 'PUT',
      'current_data': post.toJson(),
      'required_fields': ['title', 'content', 'author'],
      'optional_fields': ['slug', 'isPublished', 'tags'],
      'validation': {
        'title': 'Required, max 200 characters',
        'content': 'Required',
        'author': 'Required',
        'slug': 'Optional, auto-generated from title if not provided',
        'isPublished': 'Optional boolean',
        'tags': 'Optional, comma-separated list of tags',
      },
    });
  }
}
