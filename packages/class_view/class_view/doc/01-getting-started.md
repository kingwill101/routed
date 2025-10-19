# Getting Started

Welcome to Class View! This guide will get you up and running with Django-inspired class-based views in Dart.

## What is Class View?

Class View brings Django's elegant class-based view patterns to Dart web development. Instead of writing repetitive
request handlers, you create reusable view classes that handle common patterns like listing objects, showing details,
and processing forms.

### Why Use Class View?

**Before** (Traditional approach):

```dart
// Repetitive handler functions
router.get
('/posts
'
, (Request request) async {
final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
final posts = await repository.findAll(page: page, pageSize: 10);
return Response.ok(jsonEncode({'posts': posts, 'page': page}));
});

router.get('/posts/<id>', (Request request, String id) async {
final post = await repository.findById(id);
if (post == null) return Response.notFound('Post not found');
return Response.ok(jsonEncode(post.toJson()));
});
```

**After** (Class View approach):

```dart
// Clean, reusable view classes
class PostListView extends ListView<Post> {
  @override
  int get paginate => 10;

  @override
  Future<({List<Post> items, int total})> getObjectList({int page = 1, int pageSize = 10}) async {
    return await repository.findAll(page: page, pageSize: pageSize);
  }
}

class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await repository.findById(id);
  }
}

// Router setup
router.getView
('/posts
'
, () => PostListView());
router.getView('/posts/<id>', () => PostDetailView()
);
```

## Installation

Add Class View to your project:

```yaml
# pubspec.yaml
dependencies:
  class_view: ^0.1.0

  # Choose your framework adapter
  class_view_shelf: ^0.1.0    # For Shelf
  class_view_routed: ^0.1.0   # For Routed
```

## Your First View

Let's create a simple view that displays a welcome message:

```dart
import 'package:class_view/class_view.dart';

class WelcomeView extends View with ContextMixin {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final name = getParam('name') ?? 'World';
    sendJson({
      'message': 'Hello, $name!',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Map<String, dynamic> get extraContext =>
      {
        'app_name': 'My Awesome App',
        'version': '1.0.0',
      };
}
```

### Key Components:

- **`View`**: Base class for all views
- **`ContextMixin`**: Adds context data functionality
- **`allowedMethods`**: HTTP methods this view accepts
- **`get()`**: Handles GET requests
- **`getParam()`**: Extracts URL parameters
- **`sendJson()`**: Sends JSON responses

## Routing Setup

### With Shelf

```dart
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:class_view_shelf/class_view_shelf.dart';

void main() async {
  final router = Router();

  // Register your view - that's it!
  router.getView('/welcome', () => WelcomeView());
  router.getView('/welcome/<name>', () => WelcomeView());

  final server = await io.serve(router, 'localhost', 8080);
  print('Server running on http://localhost:8080');
}
```

### With Routed

```dart
import 'package:routed/routed.dart';
import 'package:class_view_routed/class_view_routed.dart';

void main() async {
  final app = Engine();

  // Register your view
  app.getView('/welcome', () => WelcomeView());
  app.getView('/welcome/:name', () => WelcomeView());

  await app.serve(host: 'localhost', port: 8080);
  print('Server running on http://localhost:8080');
}
```

## Testing Your View

Start your server and try these endpoints:

```bash
# Basic welcome
curl http://localhost:8080/welcome

# Welcome with name
curl http://localhost:8080/welcome/Alice
```

You'll get responses like:

```json
{
  "message": "Hello, Alice!",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "app_name": "My Awesome App",
  "version": "1.0.0"
}
```

## A Real-World Example

Let's build a simple blog post API:

```dart
// Your model
class Post {
  final String id;
  final String title;
  final String content;
  final DateTime created;

  Post({required this.id, required this.title, required this.content, required this.created});

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'title': title,
        'content': content,
        'created': created.toIso8601String(),
      };
}

// Simple repository
class PostRepository {
  static final List<Post> _posts = [
    Post(id: '1', title: 'Hello World', content: 'First post!', created: DateTime.now()),
    Post(id: '2', title: 'Getting Started', content: 'Learning Class View', created: DateTime.now()),
  ];

  static Future<List<Post>> findAll() async => _posts;

  static Future<Post?> findById(String id) async {
    return _posts
        .where((p) => p.id == id)
        .firstOrNull;
  }
}
```

### List View

```dart
class PostListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({int page = 1, int pageSize = 10}) async {
    final posts = await PostRepository.findAll();
    return (items: posts, total: posts.length);
  }
}
```

### Detail View

```dart
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await PostRepository.findById(id);
  }
}
```

### Router Setup

```dart
void setupRoutes(Router router) {
  router.getView('/posts', () => PostListView());
  router.getView('/posts/<id>', () => PostDetailView());
}
```

## How It Works

The magic happens through the **adapter pattern**:

1. **View** defines what to do (business logic)
2. **Adapter** handles how to do it (framework specifics)
3. **Router extension** connects them automatically

```dart
// When you call router.getView('/posts', () => PostListView()):
router.get
('/posts
'
, (request) async {
final view = PostListView(); // Create view
final adapter = ShelfAdapter(request); // Create adapter
view.setAdapter(adapter); // Connect them
await view.dispatch(); // Execute
return adapter.buildResponse(); // Return response
});
```

Your view stays completely framework-independent!

## Key Benefits

✅ **Less Boilerplate**: No repetitive request handling code  
✅ **Reusable**: Same view works with different frameworks  
✅ **Type Safe**: Full Dart type checking  
✅ **Testable**: Easy to unit test without HTTP layer  
✅ **Familiar**: Django developers feel right at home  
✅ **Composable**: Mix and match functionality with mixins

## What's Next?

Now that you have Class View running, explore these topics:

- **[Core Concepts](02-core-concepts.md)** - Understanding the architecture
- **[CRUD Views](04-crud-views.md)** - Build complete Create/Read/Update/Delete functionality
- **[Forms](07-forms-overview.md)** - Handle form processing and validation

Or jump to **[Basic Views](03-basic-views.md)** to learn about different view types.

---

← [Documentation Home](README.md) | **Next: [Core Concepts](02-core-concepts.md)** → 