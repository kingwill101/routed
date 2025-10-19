import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';

// Define a model class
class Post {
  final String id;
  final String title;
  final String content;
  final String author;

  Post(this.id, this.title, this.content, this.author);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'author': author,
  };
}

// Sample data repository
class PostRepository {
  static final posts = [
    Post('1', 'Hello World', 'First post content', 'John'),
    Post('2', 'Class Views', 'Class views are awesome', 'Alice'),
    Post('3', 'Dart Web', 'Building web apps with Dart', 'Bob'),
  ];

  static Future<List<Post>> getAllPosts() async => posts;

  static Future<Post?> getPostById(String id) async {
    try {
      return posts.firstWhere((post) => post.id == id);
    } catch (e) {
      return null;
    }
  }
}

// ✨ Clean DetailView - no context generics!
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await PostRepository.getPostById(id);
  }

  @override
  String get contextObjectName => 'post';
}

// ✨ Clean ListView - beautiful and simple!
class PostListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final posts = await PostRepository.getAllPosts();
    return (items: posts, total: posts.length);
  }

  @override
  String get contextObjectName => 'posts';

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'total_posts': (await PostRepository.getAllPosts()).length,
      'message': 'Posts retrieved successfully',
    };
  }
}

// ✨ API version that returns just the data
class PostApiListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final posts = await PostRepository.getAllPosts();
    return (items: posts, total: posts.length);
  }

  @override
  Future<void> get() async {
    final result = await getObjectList();
    // Simple API response - just the posts
    sendJson({
      'posts': result.items.map((p) => p.toJson()).toList(),
      'total': result.total,
    });
  }
}

void main() async {
  // Create a router
  final router = Router();

  // ✨ Beautiful, clean route registration using our extensions!
  // No boilerplate, no repetition, just pure elegance

  // List all posts (with context data)
  router.getView('/posts', () => PostListView());

  // Single post detail
  router.getView('/posts/<id>', () => PostDetailView());

  // API endpoints (clean JSON responses)
  router.getView('/api/posts', () => PostApiListView());
  router.getView('/api/posts/<id>', () => PostDetailView());

  // Root endpoint with helpful information
  router.get('/', (shelf.Request request) {
    return shelf.Response.ok(
      '''
🚀 Class View Shelf Router Example

Available endpoints:
  GET /posts      - List all posts (with extra context)
  GET /posts/1    - View single post
  GET /posts/2    - View single post  
  GET /posts/3    - View single post
  
API endpoints:
  GET /api/posts     - JSON list of posts
  GET /api/posts/1   - JSON single post

✨ Features demonstrated:
  • Clean DetailView<Post> syntax (no context generics!)
  • Framework-agnostic views
  • Automatic route parameter extraction
  • Django-inspired patterns
  • Zero boilerplate route registration
  • Multiple response formats (context vs pure JSON)
''',
      headers: {'content-type': 'text/plain'},
    );
  });

  // Create a handler pipeline with logging
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(router.call);

  // Start the server
  final server = await io.serve(handler, 'localhost', 8081);
  print('🚀 Server running on http://${server.address.host}:${server.port}');
  print('');
  print('📝 Try these endpoints:');
  print('  http://localhost:8081/           - Help');
  print('  http://localhost:8081/posts      - List posts');
  print('  http://localhost:8081/posts/1    - Post detail');
  print('  http://localhost:8081/api/posts  - API posts');
  print('');
  print('✨ Notice the clean syntax:');
  print('  • DetailView<Post> instead of DetailView<Post, Context>');
  print('  • No context parameters in methods');
  print('  • router.getView() instead of repetitive boilerplate');
  print('  • Framework-agnostic views');
}
