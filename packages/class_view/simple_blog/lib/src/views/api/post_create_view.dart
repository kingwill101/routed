import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

/// Create view for new blog posts
class PostCreateView extends CreateView<Post> {
  late final PostRepository _repository;

  PostCreateView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  String get successUrl => '/posts';

  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
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

    // Create the post
    final post = Post.fromFormData(data);
    return await _repository.create(post);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final post = object as Post;

    sendJson({
      'success': true,
      'post': post.toJson(),
      'redirect_url': '/posts/${post.slug}',
      'message': 'Post created successfully!',
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
      message = 'An unexpected error occurred while creating the post';
    }

    sendJson({
      'error': message,
      'success': false,
      'form_data': object,
    }, statusCode: statusCode);
  }

  @override
  Future<void> get() async {
    // Return form information for creating a post
    final requestUri = await getUri();
    await sendJson({
      'message': 'Create a new blog post',
      'form_action': requestUri.path,
      'form_method': 'POST',
      'required_fields': ['title', 'content', 'author'],
      'optional_fields': ['slug', 'isPublished', 'tags'],
      'example': {
        'title': 'My Awesome Blog Post',
        'content': '# Welcome\n\nThis is the content of my post...',
        'author': 'John Doe',
        'slug': 'my-awesome-blog-post',
        'isPublished': true,
        'tags': 'tutorial,web-development,dart',
      },
      'validation': {
        'title': 'Required, max 200 characters',
        'content': 'Required',
        'author': 'Required',
        'slug': 'Optional, auto-generated from title if not provided',
        'isPublished': 'Optional boolean, defaults to false',
        'tags': 'Optional, comma-separated list of tags',
      },
    });
  }
}
