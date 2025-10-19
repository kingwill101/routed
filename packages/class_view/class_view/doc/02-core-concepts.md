# Core Concepts

Understanding Class View's architecture will help you build better applications and take full advantage of its
framework-agnostic design.

## Framework-Agnostic Design

The core principle of Class View is that your business logic should be independent of any specific web framework. This
is achieved through the **adapter pattern**.

### The Problem Class View Solves

Traditional web development ties your logic to specific frameworks:

```dart
// ❌ Framework-dependent code
class PostController {
  Future<Response> getPost(Request request) async {  // Shelf-specific
    final id = request.params['id'];                 // Shelf-specific
    final post = await repository.findById(id);
    return Response.ok(jsonEncode(post));            // Shelf-specific
  }
}
```

If you want to switch from Shelf to Routed, you need to rewrite everything.

### Class View's Solution

```dart
// ✅ Framework-independent code
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');        // Framework-agnostic
    return await repository.findById(id);
  }
}

// Same view works with any framework through adapters
final shelfAdapter = ShelfAdapter(request);
final routedAdapter = RoutedAdapter(context);
final customAdapter = MyCustomAdapter(data);
```

## The Adapter Pattern

Adapters translate between your framework-agnostic views and specific web frameworks:

```dart
abstract class ViewAdapter {
  // Request information
  String get method;
  String? getParam(String name);
  Future<Map<String, dynamic>> getJsonBody();
  
  // Response operations  
  void sendJson(Map<String, dynamic> data, {int statusCode = 200});
  void redirect(String url, {int statusCode = 302});
}
```

### How Adapters Work

```dart
// Your view calls framework-agnostic methods
class MyView extends View {
  @override
  Future<void> get() async {
    final name = getParam('name');           // Adapter translates this
    sendJson({'greeting': 'Hello $name'});   // Adapter handles this
  }
}

// Shelf adapter implementation
class ShelfAdapter implements ViewAdapter {
  @override
  String? getParam(String name) => request.params[name];
  
  @override
  void sendJson(Map<String, dynamic> data, {int statusCode = 200}) {
    // Convert to Shelf Response
  }
}

// Routed adapter implementation  
class RoutedAdapter implements ViewAdapter {
  @override
  String? getParam(String name) => context.params[name];
  
  @override
  void sendJson(Map<String, dynamic> data, {int statusCode = 200}) {
    // Convert to Routed response
  }
}
```

## Clean Generic Syntax

One of Class View's key goals is eliminating verbose generic syntax:

### The Problem with Traditional Approaches

```dart
// ❌ Verbose and framework-coupled
class PostCreateView<TPost, TContext> extends CreateView<TPost, TContext> {
  @override
  Future<TPost> createObject(Map<String, dynamic> data, TContext context) async {
    // Context parameter pollutes the API
    return repository.create(data);
  }
}

// Usage requires explicit generics
final view = PostCreateView<Post, ShelfContext>();
```

### Class View's Clean Approach

```dart
// ✅ Clean and simple
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> createObject(Map<String, dynamic> data) async {
    // No context pollution - framework-agnostic
    return repository.create(data);
  }
}

// Usage is natural
final view = PostCreateView();
```

The context is handled internally by the adapter, keeping your view logic clean.

## View Architecture

Class View uses a clean inheritance pattern with internal mixins to provide functionality:

### Base View Class

```dart
// The foundation for all views
class View {
  // Core request/response handling
  Future<void> dispatch() async {
    await setup();
    switch (method.toUpperCase()) {
      case 'GET':    await get(); break;
      case 'POST':   await post(); break;
      case 'PUT':    await put(); break;
      case 'DELETE': await delete(); break;
      default:       throw HttpException.methodNotAllowed();
    }
    await teardown();
  }
  
  // Template and form support
  void setRenderer(Renderer renderer);
  void setFormRenderer(FormRenderer renderer);
  void setWidgetRenderer(WidgetRenderer renderer);
}
```

### CRUD Views

```dart
// Create view example
class CreateView<T> extends View {
  Future<T> createObject(Map<String, dynamic> data);
  
  Future<void> post() async {
    final data = await getJsonBody();
    final object = await createObject(data);
    sendJson(object.toJson());
  }
}

// Detail view example
class DetailView<T> extends View {
  Future<T?> getObject();
  
  Future<void> get() async {
    final object = await getObject();
    if (object == null) throw HttpException.notFound();
    sendJson(object.toJson());
  }
}
```

### Benefits of the New Architecture

- **Clean Inheritance**: Views extend base classes with clear responsibilities
- **Hidden Complexity**: Mixins are used internally but hidden from users
- **Framework Agnostic**: All views work with any web framework
- **Consistent Async**: All methods are properly asynchronous
- **Standardized Error Handling**: Built-in support for HTTP exceptions

## View Lifecycle

Understanding how views process requests helps you know where to place your logic:

```dart
class MyView extends View {
  @override
  Future<void> dispatch() async {
    // 1. Setup phase
    await setup();
    
    // 2. Method dispatch
    switch (method.toUpperCase()) {
      case 'GET':    await get(); break;
      case 'POST':   await post(); break;
      case 'PUT':    await put(); break;
      case 'DELETE': await delete(); break;
      default:       throw HttpException.methodNotAllowed();
    }
    
    // 3. Cleanup phase
    await teardown();
  }
  
  // Override methods for your logic
  @override
  Future<void> setup() async {
    // Initialize resources, check permissions, etc.
  }
  
  @override
  Future<void> get() async {
    // Handle GET requests
  }
  
  @override
  Future<void> teardown() async {
    // Clean up resources, log requests, etc.
  }
}
```

### Common Override Points

```dart
class UserProfileView extends DetailView<User> {
  @override
  Future<void> setup() async {
    await super.setup();
    // Check if user can view this profile
    if (!await canViewProfile()) {
      throw HttpException.forbidden('Access denied');
    }
  }
  
  @override
  Future<User?> getObject() async {
    final userId = getParam('user_id');
    return await userRepository.findById(userId);
  }
}
```

## Context vs Framework Independence

A key design decision in Class View is avoiding "context pollution" - where framework-specific context objects leak into
your business logic.

### The Problem with Context Parameters

```dart
// ❌ Context pollution
class BadView extends View {
  Future<User> getUser(String id, ShelfContext context) async {
    // Now this method only works with Shelf
    final authHeader = context.request.headers['authorization'];
    // ...
  }
}
```

### Class View's Solution

```dart
// ✅ Framework-agnostic approach
class GoodView extends View {
  Future<User> getUser(String id) async {
    // Use adapter methods instead of direct context access
    final authHeader = getHeader('authorization');
    // This works with any framework
  }
  
  String? getHeader(String name) => adapter.getHeader(name);
}
```

The adapter provides all the framework-specific functionality you need without polluting your view logic.

## Error Handling

Class View provides consistent error handling across frameworks:

```dart
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    
    // Validation
    if (id == null || id.isEmpty) {
      throw HttpException.badRequest('Post ID is required');
    }
    
    // Fetch object
    final post = await repository.findById(id);
    
    // Not found handling is automatic in DetailView
    return post; // null becomes 404 automatically
  }
  
  @override
  Future<void> setup() async {
    // Permission checking
    if (!await hasReadPermission()) {
      throw HttpException.forbidden('Access denied');
    }
  }
}
```

HTTP exceptions are automatically converted to appropriate response codes by the adapter.

## Testing Benefits

Framework independence makes testing much easier:

```dart
// Test without any HTTP framework
test('PostDetailView returns correct post', () async {
  final view = PostDetailView();
  final mockAdapter = MockAdapter(params: {'id': '123'});
  
  view.setAdapter(mockAdapter);
  await view.dispatch();
  
  expect(mockAdapter.responseData['title'], equals('Test Post'));
  expect(mockAdapter.statusCode, equals(200));
});
```

No need to set up HTTP servers or mock complex framework objects.

## Key Principles Summary

1. **Framework Independence**: Views work with any web framework
2. **Clean APIs**: No verbose generics or context pollution
3. **Mixin Composition**: Build functionality through composition
4. **Single Responsibility**: Each component has one clear purpose
5. **Consistent Patterns**: Same patterns work everywhere
6. **Easy Testing**: Test business logic without HTTP complexity

## What's Next?

Now that you understand the core concepts, explore how to apply them:

- **[Basic Views](03-basic-views.md)** - Different view types and their purposes
- **[CRUD Views](04-crud-views.md)** - Complete Create/Read/Update/Delete patterns
- **[Mixins & Composition](05-mixins.md)** - Advanced mixin usage

---

← [Getting Started](01-getting-started.md) | **Next: [Basic Views](03-basic-views.md)** → 