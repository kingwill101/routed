// ignore_for_file: unused_import, unused_local_variable
import 'package:class_view/class_view.dart';

/// Comprehensive example demonstrating ALL refactored view types
///
/// Shows the complete clean architecture where users get simple inheritance
/// with minimal method implementations while mixins work as hidden building blocks.

// Mock models and repositories for the example
class Post {
  final String id;
  final String title;
  final String content;

  Post({required this.id, required this.title, required this.content});

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
  };
}

class PostRepository {
  static Future<Post> save(Post post) async => post;

  static Future<Post?> findById(String? id) async {
    if (id == null) return null;
    return Post(id: id, title: 'Sample Post', content: 'Content');
  }

  static Future<({List<Post> items, int total})> findAll({
    int page = 1,
    int pageSize = 10,
  }) async {
    final items = List.generate(
      pageSize,
      (i) => Post(
        id: '${(page - 1) * pageSize + i + 1}',
        title: 'Post ${(page - 1) * pageSize + i + 1}',
        content: 'Content ${(page - 1) * pageSize + i + 1}',
      ),
    );
    return (items: items, total: 100);
  }

  static Future<void> delete(String id) async {}

  static Future<Post> update(String id, Map<String, dynamic> data) async {
    return Post(id: id, title: data['title'], content: data['content']);
  }
}

class StatsService {
  static Future<Map<String, int>> getStats() async {
    return {'users': 1500, 'posts': 3200, 'comments': 8500};
  }
}

// ============================================================================
// 1. CRUD VIEWS - Already refactored, shown for completeness
// ============================================================================

/// Clean CRUD views with single method implementations
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    final post = Post.fromJson(data);
    return await PostRepository.save(post);
  }

  @override
  String get successUrl => '/posts';
}

class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }
}

class PostListView extends ListView<Post> {
  @override
  int get paginate => 10;

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    return await PostRepository.findAll(page: page, pageSize: pageSize);
  }
}

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
}

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
}

// ============================================================================
// 2. TEMPLATE VIEWS - Clean template rendering
// ============================================================================

/// Simple TemplateView for static pages
class AboutView extends TemplateView {
  @override
  String get templateName => 'about.html';

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'company': 'Acme Corporation',
      'founded': '2020',
      'mission': 'Building awesome software',
    };
  }
}

/// TemplateDetailView for object-based template rendering
class PostTemplateDetailView extends TemplateDetailView<Post> {
  @override
  String get templateName => 'posts/detail.html';

  @override
  ViewEngine? get viewEngine => TemplateManager.engine;

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {'page_title': 'Post Details', 'show_comments': true};
  }
}

// ============================================================================
// 3. CONTEXT VIEWS - JSON API endpoints
// ============================================================================

/// Simple ContextView for API endpoints
class StatsApiView extends ContextView {
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final stats = await StatsService.getStats();
    return {'stats': stats, 'timestamp': DateTime.now().toIso8601String()};
  }
}

/// Complex ContextView with multiple data sources
class DashboardApiView extends ContextView {
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final stats = await StatsService.getStats();
    final recentPosts = await PostRepository.findAll(pageSize: 5);

    return {
      'stats': stats,
      'recent_posts': recentPosts.items,
      'user_authenticated': true, // Would check real auth
    };
  }
}

// ============================================================================
// 4. REDIRECT VIEWS - Clean redirects
// ============================================================================

/// Static redirect
class LoginRedirectView extends RedirectView {
  @override
  String get redirectUrl => '/dashboard';

  @override
  bool get permanent => false;
}

/// Dynamic redirect with parameters
class PostRedirectView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    final id = await getParam('id');
    return '/posts/$id/details';
  }

  @override
  bool get preserveQueryString => true;
}

/// Conditional redirect
class ConditionalRedirectView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    final userType = await getParam('type');
    return userType == 'admin' ? '/admin/dashboard' : '/user/dashboard';
  }
}

// ============================================================================
// 5. GENERIC VIEWS - Combined functionality
// ============================================================================

/// GenericView with template rendering
class DashboardView extends GenericView {
  @override
  String get templateName => 'dashboard.html';

  @override
  ViewEngine? get viewEngine => TemplateManager.engine;

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final stats = await StatsService.getStats();
    final recentPosts = await PostRepository.findAll(pageSize: 5);

    return {
      'stats': stats,
      'recent_posts': recentPosts.items,
      'page_title': 'Dashboard',
    };
  }
}

/// GenericView with JSON API fallback (no template)
class FlexibleApiView extends GenericView {
  // No templateName - will return JSON
  @override
  String? get templateName => null;

  @override
  ViewEngine? get viewEngine => TemplateManager.engine;

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final format = await getParam('format');
    final data = await StatsService.getStats();

    return {'data': data, 'format': format ?? 'json', 'version': '1.0'};
  }
}

/// GenericView with conditional rendering
class SmartView extends GenericView {
  @override
  String? get templateName {
    // Could be set dynamically based on request
    return null; // Will return JSON by default
  }

  @override
  ViewEngine? get viewEngine => TemplateManager.engine;

  @override
  Future<void> get() async {
    final acceptsHtml =
        (await getHeader('Accept'))?.contains('text/html') ?? false;

    if (acceptsHtml) {
      // Return HTML for browser requests
      final contextData = await getContextData();
      final resp = response();
      await resp.view('flexible.html', contextData);
    } else {
      // Return JSON for API requests
      await super.get();
    }
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'message': 'This view adapts to request type',
      'data': await StatsService.getStats(),
    };
  }
}

// ============================================================================
// FRAMEWORK INTEGRATION EXAMPLES
// ============================================================================

void routingExamples() {
  // With Routed framework:
  /*
  final app = Engine();

  // CRUD routes
  app.get('/posts', PostListView());
  app.get('/posts/:id', PostDetailView());
  app.route('/posts/create', ['GET', 'POST'], PostCreateView());
  app.route('/posts/:id/edit', ['GET', 'PUT'], PostUpdateView());
  app.route('/posts/:id/delete', ['GET', 'DELETE'], PostDeleteView());

  // Template routes
  app.get('/about', AboutView());
  app.get('/posts/:id/view', PostTemplateDetailView());

  // API routes
  app.get('/api/stats', StatsApiView());
  app.get('/api/dashboard', DashboardApiView());

  // Redirect routes
  app.get('/login', LoginRedirectView());
  app.get('/go/:id', PostRedirectView());

  // Generic routes
  app.get('/dashboard', DashboardView());
  app.get('/api/flexible', FlexibleApiView());
  app.get('/smart', SmartView());
  */
}

// ============================================================================
// EXPECTED RESPONSES EXAMPLES
// ============================================================================

void responseExamples() {
  // CRUD API responses (JSON)
  final listResponse = {
    'object_list': [
      {'id': '1', 'title': 'Post 1'},
    ],
    'paginator': {'count': 100, 'num_pages': 10},
  };

  final detailResponse = {
    'post': {'id': '1', 'title': 'Post 1', 'content': 'Content'},
  };

  // Template responses (HTML)
  final aboutHtml = '''
  <html>
    <body>
      <h1>About Acme Corporation</h1>
      <p>Founded: 2020</p>
      <p>Mission: Building awesome software</p>
    </body>
  </html>
  ''';

  // API responses (JSON)
  final statsResponse = {
    'stats': {'users': 1500, 'posts': 3200},
    'timestamp': '2024-01-01T12:00:00Z',
  };

  // Redirect responses (302/301)
  // Status: 302 Found
  // Location: /dashboard
}

// ============================================================================
// ARCHITECTURE SUMMARY
// ============================================================================

/// What This Refactoring Achieves:
///
/// ✅ **Complete View Coverage**
/// - CRUD views: CreateView<T>, DetailView<T>, ListView<T>, UpdateView<T>, DeleteView<T>
/// - Template views: TemplateView, TemplateDetailView<T>
/// - API views: ContextView
/// - Redirect views: RedirectView
/// - Generic views: GenericView (combines all functionality)
///
/// ✅ **Clean User Interface**
/// - Single method implementations: getObject(), performCreate(), getExtraContext()
/// - No complex mixin compositions exposed to users
/// - Simple inheritance patterns: extends CreateView<Post>
/// - Optional customization through overrides
///
/// ✅ **Hidden Complexity**
/// - Mixins work as internal building blocks behind the scenes
/// - Context handling, pagination, error handling all automatic
/// - Framework adapters completely abstracted away
/// - Template rendering integration seamless
///
/// ✅ **Response Format Flexibility**
/// - JSON APIs by default (CRUD, Context views)
/// - HTML templates when needed (Template views)
/// - Redirects for form processing (Redirect views)
/// - Mixed functionality (Generic views)
///
/// ✅ **Framework Agnostic**
/// - Same view code works with Routed, Shelf, or any framework
/// - Adapters handle framework-specific request/response logic
/// - Views focus purely on business logic
///
/// This completes the refactoring of ALL view types in the class_view package!
/// Users now have a complete toolkit of clean, Django-inspired views with
/// hidden complexity and maximum flexibility.
