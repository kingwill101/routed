import 'package:routed/routed.dart';
import 'package:routed_class_view/routed_class_view.dart';

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

  static Future<Post> createPost(Map<String, dynamic> data) async {
    final id = (posts.length + 1).toString();
    final post = Post(
      id,
      data['title'] as String,
      data['content'] as String,
      data['author'] as String,
    );
    posts.add(post);
    return post;
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

// ✨ Clean CreateView - no context parameters!
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    return await PostRepository.createPost(data);
  }

  @override
  String get successUrl => '/posts';

  @override
  Future<void> post() async {
    try {
      final data = await getJsonBody();
      final post = await performCreate(data);

      // Send JSON response with the created post
      sendJson({
        'message': 'Post created successfully',
        'post': post.toJson(),
        'redirect_url': '/posts/${post.id}',
      });
    } catch (e) {
      setStatusCode(422);
      sendJson({'error': 'Failed to create post', 'details': e.toString()});
    }
  }
}

void main() async {
  // Create an engine with routes
  final app = Engine(
    middlewares: [(EngineContext context, Next next) => next()],
  );

  // ✨ Clean route registration using RoutedViewHandler
  app.getView('/posts', () => PostListView());
  app.get('/posts/:id', RoutedViewHandler.handle(() => PostDetailView()));
  app.post('/posts/create', RoutedViewHandler.handle(() => PostCreateView()));

  // Root endpoint with helpful information
  app.get('/', (context) async {
    context.html('''
    <!DOCTYPE html>
    <html>
    <head><title>Routed Class View Example</title></head>
    <body>
      <h1>🚀 Class View Routed Engine Example</h1>
      
      <h2>Available endpoints:</h2>
      <ul>
        <li><a href="/posts">GET /posts</a> - List all posts (with extra context)</li>
        <li>GET /posts/1 - View single post</li>
        <li>GET /posts/2 - View single post</li>  
        <li>GET /posts/3 - View single post</li>
        <li>POST /posts/create - Create new post (send JSON)</li>
      </ul>
      
      <h2>✨ Features demonstrated:</h2>
      <ul>
        <li>✅ Clean DetailView&lt;Post&gt; syntax (no context generics!)</li>
        <li>✅ Framework-agnostic views</li>
        <li>✅ Automatic route parameter extraction</li>
        <li>✅ Django-inspired patterns</li>
        <li>✅ Zero boilerplate route registration</li>
        <li>✅ Multiple response formats</li>
      </ul>
      
      <h2>Try creating a post:</h2>
      <pre>
curl -X POST http://localhost:8080/posts/create \\
  -H "Content-Type: application/json" \\
  -d '{"title":"New Post","content":"Great content","author":"You"}'
      </pre>
    </body>
    </html>
    ''');
  });

  // Start the server
  await app.serve(host: 'localhost', port: 8080);
  print('🚀 Server running on http://localhost:8080');
  print('');
  print('📝 Try these endpoints:');
  print('  http://localhost:8080/           - Help');
  print('  http://localhost:8080/posts      - List posts');
  print('  http://localhost:8080/posts/1    - Post detail');
  print('');
  print('✨ Notice the clean syntax:');
  print('  • DetailView<Post> instead of DetailView<Post, Context>');
  print('  • No context parameters in methods');
  print('  • RoutedViewHandler.handle() instead of repetitive boilerplate');
  print('  • Framework-agnostic views');
}
