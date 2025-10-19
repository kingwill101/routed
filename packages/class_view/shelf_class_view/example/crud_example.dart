import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';

/// A simple blog post model
class Post {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Post copyWith({String? title, String? content}) {
    return Post(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }
}

/// Repository for managing blog posts
class PostRepository {
  final _posts = <String, Post>{
    '1': Post(
      id: '1',
      title: 'First Post',
      content: 'This is the first post content.',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    '2': Post(
      id: '2',
      title: 'Second Post',
      content: 'This is the second post content.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  };

  /// Get all posts
  Future<({List<Post> items, int total})> getAllPosts({
    int? page,
    int? pageSize,
  }) async {
    final items = _posts.values.toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (page != null && pageSize != null) {
      final start = (page - 1) * pageSize;
      final end = start + pageSize;
      final paginatedItems = items.length > start
          ? items.sublist(start, end < items.length ? end : items.length)
          : <Post>[];
      return (items: paginatedItems, total: items.length);
    }

    return (items: items, total: items.length);
  }

  /// Get post by ID
  Future<Post?> getPostById(String id) async {
    return _posts[id];
  }

  /// Create a new post
  Future<Post> createPost(Map<String, dynamic> data) async {
    final keys = _posts.keys.map((k) => int.parse(k)).toList();
    keys.sort((a, b) => b.compareTo(a));
    final id = (keys.first + 1).toString();

    final post = Post(
      id: id,
      title: data['title'] as String,
      content: data['content'] as String,
    );

    _posts[id] = post;
    return post;
  }

  /// Update an existing post
  Future<Post> updatePost(Post post, Map<String, dynamic> data) async {
    final updatedPost = post.copyWith(
      title: data['title'] as String,
      content: data['content'] as String,
    );

    _posts[post.id] = updatedPost;
    return updatedPost;
  }

  /// Delete a post
  Future<void> deletePost(String id) async {
    _posts.remove(id);
  }

  Future<void> addSampleData() async {
    // Implementation of addSampleData method
  }
}

/// Example view implementations demonstrating the new response system
class PostListView extends ListView<Post> {
  final PostRepository repository;

  PostListView(this.repository);

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final result = await repository.getAllPosts(page: page, pageSize: pageSize);
    return result;
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();

    // Check if client wants JSON (API request)
    final acceptHeader = (getHeader('Accept') as String?) ?? '';
    if (acceptHeader.contains('application/json')) {
      // 🔥 JSON API response
      response().json(contextData);
    } else {
      // 🎨 HTML response with template
      response().view('posts/list.html', {
        'title': 'All Posts',
        'posts': contextData['object_list'],
        'total': contextData['total'],
      });
    }
  }
}

class PostDetailView extends DetailView<Post> {
  final PostRepository repository;

  PostDetailView(this.repository);

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await repository.getPostById(id);
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();

    // Check if client wants JSON (API request)
    final acceptHeader = (getHeader('Accept') as String?) ?? '';
    if (acceptHeader.contains('application/json')) {
      // 🔥 JSON API response
      response().json(contextData);
    } else {
      // 🎨 HTML response with template
      response().view('posts/detail.html', {
        'title': 'Post Details',
        'post': contextData['post'],
      });
    }
  }
}

class PostCreateView extends CreateView<Post> {
  final PostRepository repository;

  PostCreateView(this.repository);

  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    return await repository.createPost(data);
  }

  Future<Post> createObject(Map<String, dynamic> data) async {
    return await repository.createPost(data);
  }

  @override
  Future<void> get() async {
    // 🎨 Show create form using Django-style template
    response().view('posts/create_form.html', {
      'title': 'Create New Post',
      'form_action': '/posts/create',
      'form_method': 'POST',
    });
  }

  @override
  Future<void> post() async {
    try {
      final data = await getFormData();
      final post = await createObject(data);

      // Check if client wants JSON response
      final acceptHeader = (getHeader('Accept') as String?) ?? '';
      if (acceptHeader.contains('application/json')) {
        // 🔥 JSON API response
        response().status(201).json({
          'message': 'Post created successfully',
          'post': post.toJson(),
        });
      } else {
        // 🎯 Redirect to the new post (Django-style)
        response().status(201).redirect('/posts/${post.id}');
      }
    } catch (e) {
      // 🚨 Show form with validation errors
      response().status(422).view('posts/create_form.html', {
        'title': 'Create New Post - Please fix errors',
        'form_action': '/posts/create',
        'form_method': 'POST',
        'errors': [e.toString()],
      });
    }
  }
}

class PostUpdateView extends UpdateView<Post> {
  final PostRepository repository;

  PostUpdateView(this.repository);

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await repository.getPostById(id);
  }

  @override
  Future<Post> performUpdate(Post object, Map<String, dynamic> data) async {
    return await repository.updatePost(object, data);
  }

  Future<Post> updateObject(Post object, Map<String, dynamic> data) async {
    return await repository.updatePost(object, data);
  }

  @override
  Future<void> get() async {
    final post = await getObjectOr404();

    // 🎨 Show edit form pre-filled with existing data
    response().view('posts/edit_form.html', {
      'title': 'Edit Post: ${post.title}',
      'post': post.toJson(),
      'form_action': '/posts/${post.id}/edit',
      'form_method': 'PUT',
    });
  }

  @override
  Future<void> put() async {
    try {
      final object = await getObjectOr404();
      final data = await getFormData();
      final updated = await updateObject(object, data);

      // Check if client wants JSON response
      final acceptHeader = (getHeader('Accept') as String?) ?? '';
      if (acceptHeader.contains('application/json')) {
        // 🔥 JSON API response
        response().json({
          'message': 'Post updated successfully',
          'post': updated.toJson(),
        });
      } else {
        // 🎯 Redirect to the updated post
        response().redirect('/posts/${updated.id}');
      }
    } catch (e) {
      final post = await getObjectOr404();

      // 🚨 Show form with validation errors
      response().status(422).view('posts/edit_form.html', {
        'title': 'Edit Post: ${post.title} - Please fix errors',
        'post': post.toJson(),
        'form_action': '/posts/${post.id}/edit',
        'form_method': 'PUT',
        'errors': [e.toString()],
      });
    }
  }
}

class PostDeleteView extends DeleteView<Post> {
  final PostRepository repository;

  PostDeleteView(this.repository);

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await repository.getPostById(id);
  }

  @override
  Future<void> performDelete(Post object) async {
    await repository.deletePost(object.id);
  }

  Future<void> deleteObject(Post object) async {
    await repository.deletePost(object.id);
  }

  @override
  Future<void> get() async {
    final post = await getObjectOr404();

    // 🎨 Show delete confirmation page
    response().view('posts/delete_confirm.html', {
      'title': 'Delete Post: ${post.title}',
      'post': post.toJson(),
      'form_action': '/posts/${post.id}/delete',
      'form_method': 'DELETE',
    });
  }

  @override
  Future<void> delete() async {
    try {
      final object = await getObjectOr404();
      await deleteObject(object);

      // Check if client wants JSON response
      final acceptHeader = (getHeader('Accept') as String?) ?? '';
      if (acceptHeader.contains('application/json')) {
        // 🔥 JSON API response
        response().json({'message': 'Post deleted successfully'});
      } else {
        // 🎯 Redirect to posts list
        response().redirect('/posts');
      }
    } catch (e) {
      final post = await getObjectOr404();

      // 🚨 Show confirmation page with error
      response().status(422).view('posts/delete_confirm.html', {
        'title': 'Delete Post: ${post.title} - Error occurred',
        'post': post.toJson(),
        'form_action': '/posts/${post.id}/delete',
        'form_method': 'DELETE',
        'errors': [e.toString()],
      });
    }
  }
}

/// Set up routes using the clean class_view integration
Router setupRoutes(PostRepository repository) {
  final router = Router();

  // ✨ Clean, simple route registration using class_view extensions!
  // No more repetitive boilerplate code

  // List all posts
  router.getView('/posts', () => PostListView(repository));

  // Create post (handles both GET for form and POST for submission)
  router.allView('/posts/create', () => PostCreateView(repository));

  // View single post
  router.getView('/posts/<id>', () => PostDetailView(repository));

  // Update post (handles GET for form, PUT/PATCH for submission)
  router.allView('/posts/<id>/edit', () => PostUpdateView(repository));

  // Delete post (handles GET for confirmation, DELETE for deletion)
  router.allView('/posts/<id>/delete', () => PostDeleteView(repository));

  return router;
}

void main() async {
  // Initialize repository with sample data
  final repository = PostRepository();
  await repository.addSampleData();

  // ✨ Clean route setup - just one line!
  final router = setupRoutes(repository);

  // Start the server
  await shelf_io.serve(router.call, 'localhost', 8080);
  print('🚀 Server running at http://localhost:8080');
  print('\n📝 Try these endpoints:');
  print('  GET  /posts           - List all posts');
  print('  GET  /posts/create    - Create post form');
  print('  POST /posts/create    - Submit new post');
  print('  GET  /posts/1         - View post details');
  print('  GET  /posts/1/edit    - Edit post form');
  print('  PUT  /posts/1         - Update post');
  print('  GET  /posts/1/delete  - Delete confirmation');
  print('  DELETE /posts/1       - Delete post');
}
