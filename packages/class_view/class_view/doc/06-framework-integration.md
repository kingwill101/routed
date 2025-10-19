# Framework Integration

Class View's framework-agnostic design allows you to use the same views with different web frameworks. This guide shows
you how to integrate with popular Dart frameworks.

## Shelf Integration

Shelf is a popular HTTP server framework. Class View provides seamless integration through router extensions.

### Basic Setup

```dart
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:class_view_shelf/class_view_shelf.dart';

void main() async {
  final router = Router();
  
  // Use router extensions for clean registration
  router.getView('/posts', () => PostListView());
  router.getView('/posts/<id>', () => PostDetailView());
  router.allView('/posts/create', () => PostCreateView());
  
  final server = await io.serve(router, 'localhost', 8080);
  print('Server running on http://localhost:8080');
}
```

### Router Extensions

The Shelf adapter provides convenient router extensions:

```dart
// Single HTTP method
router.getView('/posts', () => PostListView());
router.postView('/posts', () => PostCreateView());
router.putView('/posts/<id>', () => PostUpdateView());
router.deleteView('/posts/<id>', () => PostDeleteView());

// Multiple methods (view handles method routing)
router.allView('/posts/create', () => PostCreateView()); // GET shows form, POST creates
router.allView('/posts/<id>/edit', () => PostUpdateView()); // GET shows form, PUT/PATCH updates

// With route parameters in constructor
router.getViewWithParams('/posts/<id>', (params) => 
  PostDetailView(postId: params['id']!)
);
```

### Middleware Integration

Class View works seamlessly with Shelf middleware:

```dart
import 'package:shelf/shelf.dart';

void main() async {
  final router = Router();
  
  // Add your views
  router.getView('/api/posts', () => PostAPIView());
  router.getView('/admin/users', () => AdminUserView());
  
  // Create middleware pipeline
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(authMiddleware())
      .addHandler(router.call);
  
  await io.serve(handler, 'localhost', 8080);
}

// Custom authentication middleware
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.url.path.startsWith('/admin/')) {
        final authHeader = request.headers['authorization'];
        if (!await isValidToken(authHeader)) {
          return Response.forbidden('Access denied');
        }
      }
      return await innerHandler(request);
    };
  };
}
```

### Custom Response Processing

```dart
class APIView extends View {
  @override
  Future<void> get() async {
    final data = await getAPIData();
    
    // Send JSON with custom headers
    setHeader('X-API-Version', 'v1');
    setHeader('Cache-Control', 'max-age=300');
    sendJson(data);
  }
}

// Or override the adapter for global behavior
class CustomShelfAdapter extends ShelfAdapter {
  @override
  void sendJson(Map<String, dynamic> data, {int statusCode = 200}) {
    // Add custom headers to all JSON responses
    setHeader('X-Powered-By', 'Class View');
    super.sendJson(data, statusCode: statusCode);
  }
}
```

## Routed Integration

Routed is another Dart web framework. Class View integrates through engine extensions.

### Basic Setup

```dart
import 'package:routed/routed.dart';
import 'package:class_view_routed/class_view_routed.dart';

void main() async {
  final app = Engine();
  
  // Use engine extensions
  app.getView('/posts', () => PostListView());
  app.getView('/posts/:id', () => PostDetailView());
  app.postView('/posts', () => PostCreateView());
  
  await app.serve(host: 'localhost', port: 8080);
}
```

### Engine Extensions

```dart
// HTTP method specific
app.getView('/posts', () => PostListView());
app.postView('/posts', () => PostCreateView());
app.putView('/posts/:id', () => PostUpdateView());
app.deleteView('/posts/:id', () => PostDeleteView());

// All methods (view handles routing)
app.allView('/posts/manage', () => PostManagementView());

// Manual handler registration
app.get('/custom', RoutedViewHandler.handle(() => CustomView()));
```

### Parameter Extraction

Routed's parameter syntax works automatically:

```dart
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id'); // Extracts from /posts/:id
    return await postRepository.findById(id);
  }
}

class CategoryPostsView extends ListView<Post> {
  @override
  Future<List<Post>> getObjectList() async {
    final categorySlug = getParam('category'); // From /categories/:category/posts
    final category = await categoryRepository.findBySlug(categorySlug);
    
    return await postRepository.findByCategory(
      category?.id,
      page: getCurrentPage(),
      pageSize: pageSize,
    );
  }
}

// Usage
app.getView('/categories/:category/posts', () => CategoryPostsView());
```

### Configuration-aware views

The Routed adapter exposes the underlying `EngineContext`, allowing views to
read configuration values from the container. This keeps pagination, feature
flags, and other behaviour in sync with your Routed application settings.

```dart
import 'package:routed/routed.dart' show Config;
import 'package:class_view_routed/class_view_routed.dart';

class PaginatedPostListView extends ListView<Post> {
  @override
  int? get paginate {
    final routedContext = (adapter as RoutedAdapter).context;
    final config = routedContext.container.get<Config>();
    return config.get('views.pagination.page_size', 20) as int;
  }
}
```

### Middleware Integration

```dart
void main() async {
  final app = Engine(middlewares: [
    loggingMiddleware,
    corsMiddleware,
    authMiddleware,
  ]);
  
  app.getView('/api/protected', () => ProtectedAPIView());
  
  await app.serve(host: 'localhost', port: 8080);
}

### Cache helpers

Routed ships with a cache manager that integrates with the `EngineContext`. The
adapter exposes this context so you can layer caching strategies directly in
your views.

```dart
class CachedPostListView extends ListView<Post> {
  final PostRepository repository;

  CachedPostListView(this.repository);

  @override
  Future<({List<Post> items, int total})> getObjectList({int page = 1, int pageSize = 10}) async {
    final ctx = (adapter as RoutedAdapter).context;
    final cacheKey = 'posts.page.$pageSize.$page';

    final items = await ctx.rememberCache(
      cacheKey,
      Duration(minutes: 5),
      () async => repository.fetchPage(page: page, pageSize: pageSize),
    ) as List<Post>;

    final total = await repository.count();
    return (items: items, total: total);
  }
}
```

Future<void> authMiddleware(EngineContext context) async {
if (context.path.startsWith('/api/protected')) {
final token = context.headers['authorization'];
if (!await isValidToken(token)) {
context.status(403).json({'error': 'Access denied'});
return;
}
}
// Continue to next middleware/handler
}

```

## Custom Framework Integration

You can integrate Class View with any framework by creating a custom adapter.

### Creating a Custom Adapter

```dart
class MyFrameworkAdapter implements ViewAdapter {
  final MyFrameworkRequest request;
  final MyFrameworkResponse response;
  
  MyFrameworkAdapter(this.request, this.response);
  
  @override
  String get method => request.method;
  
  @override
  Uri get uri => request.uri;
  
  @override
  String? getParam(String name) => request.params[name];
  
  @override
  Map<String, String> getParams() => request.params;
  
  @override
  String? getHeader(String name) => request.headers[name];
  
  @override
  Future<String> getBody() async => await request.body;
  
  @override
  Future<Map<String, dynamic>> getJsonBody() async {
    final body = await getBody();
    return jsonDecode(body) as Map<String, dynamic>;
  }
  
  @override
  void setHeader(String name, String value) {
    response.headers[name] = value;
  }
  
  @override
  void setStatusCode(int code) {
    response.statusCode = code;
  }
  
  @override
  void write(String body) {
    response.write(body);
  }
  
  @override
  void writeJson(Map<String, dynamic> data, {int statusCode = 200}) {
    setStatusCode(statusCode);
    setHeader('Content-Type', 'application/json');
    write(jsonEncode(data));
  }
  
  @override
  void redirect(String url, {int statusCode = 302}) {
    setStatusCode(statusCode);
    setHeader('Location', url);
  }
}
```

### Using the Custom Adapter

```dart
class MyFrameworkViewHandler {
  static Future<void> handle(View view, MyFrameworkRequest request, MyFrameworkResponse response) async {
    final adapter = MyFrameworkAdapter(request, response);
    view.setAdapter(adapter);
    await view.dispatch();
  }
}

// Usage in your framework
app.get('/posts', (request, response) async {
  await MyFrameworkViewHandler.handle(PostListView(), request, response);
});
```

## Best Practices

1. **Use Framework Extensions**: Use the provided router/engine extensions for clean integration
2. **Middleware First**: Apply framework middleware before view handling
3. **Async Support**: Ensure all adapter methods are properly asynchronous
4. **Error Handling**: Use framework-specific error handling when needed
5. **Custom Adapters**: Create custom adapters for frameworks without built-in support

## What's Next?

- Learn about [Form Handling](07-forms-overview.md) for processing user input
- Explore [Templates](11-templates.md) for rendering views
- See [Testing](12-testing.md) for testing your views

---

← [Mixins & Composition](05-mixins.md) | **Next: [Forms Overview](07-forms-overview.md)** → 
