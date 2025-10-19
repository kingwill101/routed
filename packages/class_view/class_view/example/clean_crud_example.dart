// ignore_for_file: unused_import, unused_local_variable
import 'package:class_view/class_view.dart';

/// Example demonstrating the new clean CRUD view architecture
///
/// Users get clean `CreateView<Post>` syntax with single method implementations.
/// These are generic API views that work with any response format (JSON, HTML, XML, text, etc.).
/// Mixins work behind the scenes as hidden internal building blocks.

// Mock models and repositories for the example
class Post {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };

  Post copyWith({String? title, String? content}) => Post(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
  );
}

class PostRepository {
  static Future<Post> save(Post post) async {
    // Mock save operation
    return post;
  }

  static Future<Post?> findById(String? id) async {
    if (id == null) return null;
    // Mock database lookup
    return Post(
      id: id,
      title: 'Sample Post',
      content: 'This is a sample post content.',
      createdAt: DateTime.now(),
    );
  }

  static Future<({List<Post> items, int total})> findAll({
    int page = 1,
    int pageSize = 10,
  }) async {
    // Mock paginated results
    final items = List.generate(
      pageSize,
      (i) => Post(
        id: '${(page - 1) * pageSize + i + 1}',
        title: 'Post ${(page - 1) * pageSize + i + 1}',
        content: 'Content for post ${(page - 1) * pageSize + i + 1}',
        createdAt: DateTime.now(),
      ),
    );
    return (items: items, total: 100); // Mock total
  }

  static Future<Post> update(String id, Map<String, dynamic> data) async {
    final existing = await findById(id);
    if (existing == null) throw Exception('Post not found');

    return existing.copyWith(title: data['title'], content: data['content']);
  }

  static Future<void> delete(String id) async {
    // Mock delete operation
  }
}

// ============================================================================
// NEW CLEAN CRUD VIEWS - Generic API views for any response format
// ============================================================================

/// Generic CreateView - Users only implement performCreate()
/// Defaults to JSON responses but can be overridden for HTML, XML, text, etc.
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    final post = Post.fromJson(data);
    return await PostRepository.save(post);
  }

  @override
  String get successUrl => '/posts'; // Optional
}

/// Generic DetailView - Users only implement getObject()
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }
}

/// Generic ListView - Users implement getObjects() and optional pagination
class PostListView extends ListView<Post> {
  @override
  int get paginate => 10; // Optional automatic pagination

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    return await PostRepository.findAll(page: page, pageSize: pageSize);
  }
}

/// Generic UpdateView - Users implement getObject() and performUpdate()
class PostUpdateView extends UpdateView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }

  @override
  Future<Post> performUpdate(Post post, Map<String, dynamic> data) async {
    return await PostRepository.update(post.id, data);
  }

  @override
  String get successUrl => '/posts'; // Optional
}

/// Generic DeleteView - Users implement getObject() and performDelete()
class PostDeleteView extends DeleteView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }

  @override
  Future<void> performDelete(Post post) async {
    await PostRepository.delete(post.id);
  }

  @override
  String get successUrl => '/posts'; // Optional
}

// ============================================================================
// CUSTOM RESPONSE FORMAT EXAMPLES
// ============================================================================

/// Example: Custom HTML response instead of JSON
class PostCreateHtmlView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    final post = Post.fromJson(data);
    return await PostRepository.save(post);
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    // Override to return HTML response instead of JSON
    final resp = response();
    resp.html('<form>Create Post Form HTML</form>');
  }
}

/// Example: Custom XML API response
class PostListXmlView extends ListView<Post> {
  @override
  int get paginate => 10;

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    return await PostRepository.findAll(page: page, pageSize: pageSize);
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    // Override to return XML response instead of JSON
    final posts = contextData['object_list'] as List<Post>;
    final xml =
        '<posts>${posts.map((p) => '<post><id>${p.id}</id><title>${p.title}</title></post>').join()}</posts>';

    final resp = response();
    resp.status(200).header('Content-Type', 'application/xml').text(xml);
  }
}

/// Example: Custom plain text response
class PostDetailTextView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    final post = contextData['post'] as Post;

    // Override to return plain text response
    final text = 'Post: ${post.title}\n\n${post.content}';
    final resp = response();
    resp.text(text);
  }
}

// ============================================================================
// FRAMEWORK INTEGRATION EXAMPLES
// ============================================================================

/// Example Routed integration (would be in routed_class_view package)
void routedIntegrationExample() {
  // This is how users would integrate with Routed framework:
  /*
  import 'package:routed/routed.dart';
  import 'package:routed_class_view/routed_class_view.dart';

  final app = Engine();

  // Clean, simple view registration
  app.get('/posts', PostListView());
  app.get('/posts/:id', PostDetailView());
  app.route('/posts/create', ['GET', 'POST'], PostCreateView());
  app.route('/posts/:id/edit', ['GET', 'PUT', 'PATCH'], PostUpdateView());
  app.route('/posts/:id/delete', ['GET', 'DELETE'], PostDeleteView());
  */
}

/// Example Shelf integration (would be in shelf_class_view package)
void shelfIntegrationExample() {
  // This is how users would integrate with Shelf framework:
  /*
  import 'package:shelf/shelf.dart';
  import 'package:shelf_router/shelf_router.dart';
  import 'package:shelf_class_view/shelf_class_view.dart';

  final router = Router();

  // Clean, simple view registration
  router.get('/posts', createHandler(PostListView()));
  router.get('/posts/<id>', createHandler(PostDetailView()));
  router.get('/posts/create', createHandler(PostCreateView()));
  router.post('/posts/create', createHandler(PostCreateView()));
  router.get('/posts/<id>/edit', createHandler(PostUpdateView()));
  router.put('/posts/<id>/edit', createHandler(PostUpdateView()));
  router.patch('/posts/<id>/edit', createHandler(PostUpdateView()));
  router.get('/posts/<id>/delete', createHandler(PostDeleteView()));
  router.delete('/posts/<id>/delete', createHandler(PostDeleteView()));
  */
}

// ============================================================================
// EXPECTED API RESPONSES
// ============================================================================

/// Example responses from the clean CRUD views

void expectedResponsesExample() {
  // GET /posts (PostListView)
  final listResponse = {
    'object_list': [
      {'id': '1', 'title': 'Post 1', 'content': '...'},
      {'id': '2', 'title': 'Post 2', 'content': '...'},
    ],
    'paginator': {'count': 100, 'num_pages': 10, 'page_size': 10},
  };

  // GET /posts/1 (PostDetailView)
  final detailResponse = {
    'post': {'id': '1', 'title': 'Post 1', 'content': '...'},
  };

  // GET /posts/create (PostCreateView)
  final createFormResponse = {
    'form_action': '/posts/create',
    'form_method': 'POST',
  };

  // POST /posts/create (PostCreateView) - Success
  final createSuccessResponse = {
    'success': true,
    'message': 'Operation completed successfully',
  };

  // GET /posts/1/edit (PostUpdateView)
  final updateFormResponse = {
    'post': {'id': '1', 'title': 'Post 1', 'content': '...'},
    'form_action': '/posts/1/edit',
    'form_method': 'PUT',
  };

  // GET /posts/1/delete (PostDeleteView)
  final deleteConfirmResponse = {
    'post': {'id': '1', 'title': 'Post 1', 'content': '...'},
    'confirmation_message': 'Are you sure you want to delete this object?',
    'form_action': '/posts/1/delete',
    'form_method': 'DELETE',
  };
}

// ============================================================================
// ARCHITECTURE SUMMARY
// ============================================================================

/// What This Architecture Achieves:
///
/// ✅ **Clean User Interface**
/// - Users extend `CreateView<Post>` instead of complex mixin compositions
/// - Single method implementations: `performCreate()`, `getObject()`, etc.
/// - No exposure to adapter or context complexity
///
/// ✅ **Generic API Views**
/// - Work with any response format: JSON, HTML, XML, text, etc.
/// - Default to JSON but easily overridable for other formats
/// - Not tied to specific response types or frameworks
/// - True API flexibility for any use case
///
/// ✅ **Hidden Complexity**
/// - Mixins work as internal building blocks behind the scenes
/// - Context handling, pagination, error handling all automatic
/// - Framework adapters completely abstracted away
///
/// ✅ **Framework Agnostic**
/// - Same view code works with Routed, Shelf, or any other framework
/// - Adapters handle framework-specific request/response logic
/// - Views focus purely on business logic
///
/// ✅ **Type Safe**
/// - Full generic type safety with `CreateView<Post>`
/// - No verbose generic signatures like `CreateView<Post, Context>`
/// - IDE support and autocomplete work perfectly
///
/// ✅ **Composable and Extensible**
/// - Mixins can be composed for custom functionality internally
/// - Views can be extended for specialized behavior
/// - Custom response formats easy to implement
/// - New view types can be created by combining existing mixins
///
/// This is the clean, Django-inspired architecture we set out to achieve!
