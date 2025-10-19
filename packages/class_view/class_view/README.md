# Class View

🏗️ **Django-inspired class-based views for Dart web frameworks**

A powerful, framework-agnostic package that brings Django's elegant class-based view patterns to Dart. Build clean,
composable web applications with minimal boilerplate and maximum flexibility.

## ✨ Key Features

- 🎯 **Clean Syntax**: `CreateView<Post>` instead of verbose generics
- 🔧 **Framework Agnostic**: Works with any web framework through adapters
- 🏛️ **Django-Inspired**: Familiar patterns for developers coming from Django
- 🧩 **Composable Mixins**: Mix and match functionality without inheritance hell
- 📝 **Complete CRUD**: Ready-to-use Create, Read, Update, Delete views
- ⚡ **Type Safe**: Full Dart type safety with clean APIs
- 🧪 **Test Friendly**: Comprehensive testing with [server_testing](https://pub.dev/packages/server_testing) integration

## 🚀 Quick Start

### Installation

```yaml
dependencies:
  class_view: ^0.1.0
  class_view_shelf: ^0.1.0  # For Shelf integration
```

### Basic Example

```dart
import 'package:class_view/class_view.dart';
import 'package:class_view/shelf_adapter.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

// Define your model
class Post {
  final String id;
  final String title;
  final String content;
  
  Post({required this.id, required this.title, required this.content});
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title, 
    'content': content,
  };
}

// Create views with clean, minimal syntax
class PostListView extends ListView<Post> {
  @override
  int get paginate => 10;
  
  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1, 
    int pageSize = 10
  }) async {
    // Fetch your posts from database/repository
    final posts = await PostRepository.findAll(page: page, pageSize: pageSize);
    return (items: posts, total: await PostRepository.count());
  }
}

class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await PostRepository.findById(id);
  }
}

class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> createObject(Map<String, dynamic> data) async {
    return await PostRepository.create(data);
  }
  
  @override
  String get successUrl => '/posts';
}

// Set up routing with any framework
void main() {
  final router = Router();
  
  // ✨ Clean route registration using class_view extensions!
  router.getView('/posts', () => PostListView());
  router.getView('/posts/<id>', () => PostDetailView());
  router.allView('/posts/create', () => PostCreateView()); // Handles GET and POST
  
  serve(router, 'localhost', 8080);
}

// The extensions are automatically available when you import the shelf adapter
import 'package:class_view/shelf_adapter.dart';

## 🏗️ Architecture Overview

### Framework-Agnostic Design

Views operate independently of any specific web framework through the **Adapter Pattern**:

```dart
// Your view code stays the same regardless of framework
class MyView extends DetailView<User> {
  @override
  Future<User?> getObject() async {
    final id = getParam('id');  // Framework agnostic!
    return await userRepo.findById(id);
  }
}

// Different adapters for different frameworks
final shelfAdapter = ShelfAdapter(request);      // For Shelf
final routedAdapter = RoutedAdapter(context);    // For Routed
final customAdapter = MyCustomAdapter(data);     // For your framework

view.setAdapter(adapter);
await view.dispatch();
```

### Clean Generic Syntax

**Before** (Verbose):

```dart
class PostCreateView extends CreateView<Post, ShelfContext> {
  Future<Post> createObject(Map<String, dynamic> data, ShelfContext context) async {
    // Implementation
  }
}
```

**After** (Clean):

```dart
class PostCreateView extends CreateView<Post> {
  Future<Post> createObject(Map<String, dynamic> data) async {
    // Implementation - no context pollution!
  }
}
```

## 📚 Complete CRUD Example

See our comprehensive [Todo App Example](test/todo_app/) that demonstrates:

- ✅ **Full CRUD Operations**: Create, Read, Update, Delete
- ✅ **Pagination & Filtering**: Built-in list view features
- ✅ **Search Functionality**: Search across multiple fields
- ✅ **Validation**: Comprehensive input validation
- ✅ **Error Handling**: Proper HTTP status codes and error responses
- ✅ **Repository Pattern**: Clean data layer separation
- ✅ **Testing**: 24/24 tests passing with [server_testing](https://pub.dev/packages/server_testing)

```dart
// Complete Todo CRUD in just a few lines!
class TodoListView extends ListView<Todo> {
  final TodoRepository repository;
  TodoListView(this.repository);
  
  @override
  int get paginate => 10;
  
  @override
  Future<({List<Todo> items, int total})> getObjectList({
    int page = 1, 
    int pageSize = 10
  }) async {
    // Handle filtering and search
    final completed = getParam('completed');
    final search = getParam('search');
    
    return await repository.findAll(
      page: page,
      pageSize: pageSize, 
      completed: completed == 'true' ? true : 
                 completed == 'false' ? false : null,
      search: search,
    );
  }
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'stats': await repository.getStats(),
      'current_filter': getParam('completed'),
      'current_search': getParam('search'),
    };
  }
}
```

## 🧩 View Types & Mixins

### Base Views

| View Type       | Purpose                  | Methods                                   |
|-----------------|--------------------------|-------------------------------------------|
| `View`          | Base class for all views | `dispatch()`, `getParam()`, `sendJson()`  |
| `ListView<T>`   | Display multiple objects | `getObjectList()`, pagination, filtering  |
| `DetailView<T>` | Display single object    | `getObject()`, 404 handling               |
| `CreateView<T>` | Create new objects       | `createObject()`, validation, success URL |
| `UpdateView<T>` | Update existing objects  | `updateObject()`, partial updates         |
| `DeleteView<T>` | Delete objects           | `deleteObject()`, confirmation            |

### Powerful Mixins

```dart
// Compose functionality with mixins
class MyView extends View 
    with ContextMixin,           // Extra context data
         SingleObjectMixin<User>, // Single object operations
         SuccessUrlMixin {        // Success redirects
  
  @override
  Future<User?> getObject() async => await userRepo.find(getParam('id'));
  
  @override
  String get successUrl => '/users';
  
  @override
  Map<String, dynamic> get extraContext => {'title': 'User Management'};
}
```

### Available Mixins

- **`ContextMixin`**: Add extra context data to responses
- **`SingleObjectMixin<T>`**: Work with single objects, automatic 404 handling
- **`MultipleObjectMixin<T>`**: Work with collections, pagination support
- **`SuccessUrlMixin`**: Handle success redirects after actions
- **`FormProcessingMixin`**: Process form data and validation

## 🧪 Testing

Comprehensive testing with [server_testing](https://pub.dev/packages/server_testing) integration:

```dart
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';

test('Todo CRUD operations', () async {
  final repository = TodoRepository();
  final app = createTodoApp(repository);
  final client = TestClient.inMemory(ShelfRequestHandler(app));
  
  try {
    // Test list view
    final listResponse = await client.get('/todos');
    listResponse
      .assertStatus(200)
      .assertJson((json) {
        json.has('object_list')
            .has('stats')
            .where('stats.total', greaterThan(0))
            .has('page_info')
            .where('page_info.current_page', 1);
      });
    
    // Test creation
    final createResponse = await client.postJson('/todos/create', {
      'title': 'Test Todo',
      'description': 'Created via test',
      'completed': false,
    });
    
    createResponse
      .assertStatus(201)
      .assertJson((json) {
        json.has('todo')
            .where('todo.title', 'Test Todo')
            .where('todo.completed', false)
            .has('message')
            .where('message', contains('created successfully'));
      });
    
  } finally {
    await client.close();
  }
});
```

## 🌐 Framework Integration

### Shelf Integration

```dart
import 'package:class_view/shelf_adapter.dart';

// ✨ Clean, one-line route registration using built-in extensions
final router = Router();

// Single HTTP method routes
router.getView('/posts', () => PostListView());
router.postView('/posts', () => PostCreateView());
router.getView('/posts/<id>', () => PostDetailView());
router.putView('/posts/<id>', () => PostUpdateView());
router.deleteView('/posts/<id>', () => PostDeleteView());

// Multi-method routes (views that handle multiple HTTP methods)
router.allView('/posts/create', () => PostCreateView()); // Handles GET and POST
router.allView('/posts/<id>/edit', () => PostUpdateView()); // Handles GET, PUT, PATCH
router.allView('/posts/<id>/delete', () => PostDeleteView()); // Handles GET and DELETE

// Route parameters in view constructor (if needed)
router.getViewWithParams('/posts/<id>', (params) => PostDetailView(params['id']!));
```

### Routed Integration

```dart
import 'package:routed/routed.dart';

extension RoutedViewExtension on Engine {
  void addView<T extends View>(String path, T Function() viewFactory) {
    route(path, (context) async {
      final view = viewFactory();
      view.setAdapter(RoutedAdapter(context));
      await view.dispatch();
    });
  }
}

// Usage  
app.addView('/posts', () => PostListView());
app.addView('/posts/<id>', () => PostDetailView());
```

## 📖 Examples

### 1. Blog Application

```dart
class BlogPostListView extends ListView<BlogPost> {
  @override
  int get paginate => 5;
  
  @override
  Future<({List<BlogPost> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final category = getParam('category');
    return await blogRepo.findAll(
      page: page, 
      pageSize: pageSize,
      category: category,
    );
  }
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'categories': await blogRepo.getCategories(),
      'featured_posts': await blogRepo.getFeatured(limit: 3),
      'current_category': getParam('category'),
    };
  }
}
```

### 2. User Management

```dart
class UserCreateView extends CreateView<User> {
  @override
  Future<User> createObject(Map<String, dynamic> data) async {
    // Validation
    if (data['email']?.isEmpty ?? true) {
      throw ValidationException('Email is required');
    }
    
    if (data['password']?.length < 8) {
      throw ValidationException('Password must be at least 8 characters');
    }
    
    // Hash password and create user
    final hashedPassword = hashPassword(data['password']);
    return await userRepo.create({
      ...data,
      'password': hashedPassword,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  
  @override
  String get successUrl => '/users';
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'roles': await roleRepo.findAll(),
      'departments': await departmentRepo.findAll(),
    };
  }
}
```

### 3. API Endpoints

```dart
class ProductApiView extends ListView<Product> {
  @override
  Future<({List<Product> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 20,
  }) async {
    final category = getParam('category');
    final minPrice = double.tryParse(getParam('min_price') ?? '');
    final maxPrice = double.tryParse(getParam('max_price') ?? '');
    final search = getParam('search');
    
    return await productRepo.findAll(
      page: page,
      pageSize: pageSize,
      category: category,
      priceRange: minPrice != null && maxPrice != null 
          ? (min: minPrice, max: maxPrice) 
          : null,
      search: search,
    );
  }
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'filters': {
        'categories': await productRepo.getCategories(),
        'price_ranges': await productRepo.getPriceRanges(),
      },
      'metadata': {
        'total_products': await productRepo.count(),
        'last_updated': DateTime.now().toIso8601String(),
      },
    };
  }
}
```

## 🔄 Migration from Old Architecture

### Before (Verbose & Coupled)

```dart
class OldPostCreateView extends CreateView<Post, ShelfContext> {
  @override
  Future<Post> createObject(Map<String, dynamic> data, ShelfContext context) async {
    // Tightly coupled to Shelf context
    final userId = context.request.headers['user-id'];
    return await postRepo.create({...data, 'user_id': userId});
  }
}
```

### After (Clean & Framework Agnostic)

```dart
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> createObject(Map<String, dynamic> data) async {
    // Framework agnostic - works with any adapter
    final userId = getParam('user_id') ?? getCurrentUserId();
    return await postRepo.create({...data, 'user_id': userId});
  }
}
```

## 🎯 Design Goals Achieved

- ✅ **Clean syntax**: `CreateView<Post>` instead of `CreateView<Post, Context>`
- ✅ **Framework agnostic**: Same view code works with any framework
- ✅ **Django-like patterns**: Familiar workflows and method names
- ✅ **Composable mixins**: Mix and match functionality without inheritance
- ✅ **Type safety**: Full Dart type checking without verbose generics
- ✅ **Testability**: Easy testing with server_testing integration
- ✅ **Performance**: Minimal overhead, maximum flexibility

## 🛠️ Development Notes

### Regenerating form templates

The massive `lib/src/view/form/template_bundle.dart` file is generated from the Liquid templates in `templates/`.
Regenerate it whenever the template assets change:

```sh
dart run tool/build_templates.dart
```

The generated output is ignored by default (see `.gitignore` in this package). Commit updates only when the generated
content materially changes to keep diffs readable.

Before publishing a release, double-check that the bundle matches the templates:

```sh
dart run tool/verify_templates.dart
```

### Optional extensions

- `class_view_image_field`: Opt-in support for `ImageField`, including decoding via the [
  `image`](https://pub.dev/packages/image) package. Add the dependency and import
  `package:class_view_image_field/class_view_image_field.dart` to enable the builder.

## 📦 Packages

| Package                | Purpose                      |
|------------------------|------------------------------|
| `class_view`           | Core class-based view system |
| `class_view_shelf`     | Shelf framework integration  |
| `server_testing`       | HTTP testing utilities       |
| `server_testing_shelf` | Shelf testing integration    |

## 🤝 Contributing

We welcome contributions! This package is part of
the [Routed Ecosystem](https://github.com/kingwill101/routed_ecosystem).

1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Ensure all tests pass
5. Create a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Built with ❤️ for the Dart community**

### Complete Example: Clean Setup

Here's how simple it is to set up a full CRUD API:

```dart
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:class_view/shelf_adapter.dart';

// Your views (clean, no boilerplate)
class PostListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({int page = 1, int pageSize = 10}) async {
    return await PostRepository.findAll(page: page, pageSize: pageSize);
  }
}

class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await PostRepository.findById(id);
  }
}

class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> createObject(Map<String, dynamic> data) async {
    return await PostRepository.create(data);
  }
}

// Setup (incredibly clean!)
void main() async {
  final router = Router();
  
  // This is ALL you need - no repetitive handler code!
  router.getView('/posts', () => PostListView());
  router.getView('/posts/<id>', () => PostDetailView());
  router.allView('/posts/create', () => PostCreateView());
  router.allView('/posts/<id>/edit', () => PostUpdateView());
  router.allView('/posts/<id>/delete', () => PostDeleteView());
  
  await io.serve(router, 'localhost', 8080);
  print('🚀 Server running at http://localhost:8080');
}

**That's it!** No manual adapter creation, no repetitive handler code, no boilerplate. The router extensions handle everything automatically.

### Different Routing Patterns

```dart
final router = Router();

// 🎯 Single HTTP method per route (most explicit)
router.getView('/posts', () => PostListView());
router.postView('/posts', () => PostCreateView());
router.getView('/posts/<id>', () => PostDetailView());
router.putView('/posts/<id>', () => PostUpdateView());
router.deleteView('/posts/<id>', () => PostDeleteView());

// 🌟 Multi-method routes (Django-style, handles GET/POST automatically)
router.allView('/posts/create', () => PostCreateView()); // GET shows form, POST creates
router.allView('/posts/<id>/edit', () => PostUpdateView()); // GET shows form, PUT/PATCH updates
router.allView('/posts/<id>/delete', () => PostDeleteView()); // GET shows confirmation, DELETE deletes

// 🔧 When you need route parameters in constructor
router.getViewWithParams('/posts/<id>', (params) => PostDetailView(postId: params['id']!));
router.getViewWithParams('/categories/<cat>/posts/<id>', (params) => 
  PostDetailView(categoryId: params['cat']!, postId: params['id']!)
);

// 🏆 Different views for different content types
router.getView('/api/posts', () => PostApiListView()); // Returns JSON
router.getView('/posts', () => PostHtmlListView()); // Returns HTML
```

### Advanced Usage

```dart
final router = Router();

// 🎯 Single HTTP method per route (most explicit)
router.getView('/posts', () => PostListView());
router.postView('/posts', () => PostCreateView());
router.getView('/posts/<id>', () => PostDetailView());
router.putView('/posts/<id>', () => PostUpdateView());
router.deleteView('/posts/<id>', () => PostDeleteView());

// 🌟 Multi-method routes (Django-style, handles GET/POST automatically)
router.allView('/posts/create', () => PostCreateView()); // GET shows form, POST creates
router.allView('/posts/<id>/edit', () => PostUpdateView()); // GET shows form, PUT/PATCH updates
router.allView('/posts/<id>/delete', () => PostDeleteView()); // GET shows confirmation, DELETE deletes

// 🔧 When you need route parameters in constructor
router.getViewWithParams('/posts/<id>', (params) => PostDetailView(postId: params['id']!));
router.getViewWithParams('/categories/<cat>/posts/<id>', (params) => 
  PostDetailView(categoryId: params['cat']!, postId: params['id']!)
);

// 🏆 Different views for different content types
router.getView('/api/posts', () => PostApiListView()); // Returns JSON
router.getView('/posts', () => PostHtmlListView()); // Returns HTML
```

## Testing

The package includes comprehensive testing utilities for file operations and request handling.

### Testing File Operations

Use `TestFormFile` for testing file uploads:

```dart
import 'package:test/test.dart';
import 'package:class_view/class_view.dart';
import 'test/mock_adapter.dart';

test
('file upload test
'
, () async {
// Create test files
final textFile = TestFormFile.fromText('document.txt', 'Hello World');
final imageFile = TestFormFile.image('avatar.jpg', size: 2048);
final emptyFile = TestFormFile.empty('empty.bin');

// Create mock adapter with files
final adapter = MockViewAdapter(
files: {
'document': textFile,
'avatar': imageFile,
'empty': emptyFile,
},
);

final request = Request(adapter);

// Test file operations
expect(request.hasFile('document'), isTrue);

final file = await request.file('document');
expect(file!.name, equals('document.txt'));
expect(file.size, equals(11)); // "Hello World" length

final allFiles = await request.files();
expect(allFiles, hasLength(3));
});
```

### Testing Combined Form Data and Files

The `MockViewAdapter` supports both form data and file uploads in a single test:

```dart
test('form data with file upload', () async {
  final uploadFile = TestFormFile.fromText('upload.txt', 'File content');
  
  final adapter = MockViewAdapter(
    method: 'POST',
    formData: {
      'title': 'Document Upload',
      'description': 'Uploading a test document',
    },
    files: {
      'attachment': uploadFile,
    },
  );
  
  final request = Request(adapter);
  
  // Test form fields
  expect(request.get('title'), equals('Document Upload'));
  expect(request.get('description'), equals('Uploading a test document'));
  
  // Test file upload
  expect(request.hasFile('attachment'), isTrue);
  final file = await request.file('attachment');
  expect(file!.name, equals('upload.txt'));
});
```

### Testing Different File Types

The `TestFormFile` class provides convenient factory methods for different file scenarios:

```dart
test
('different file types
'
, () async {
// Text file
final textFile = TestFormFile.fromText('notes.txt', 'Meeting notes');

// Image file
final imageFile = TestFormFile.image('photo.jpg', size: 1024 * 1024); // 1MB

// Empty file
final emptyFile = TestFormFile.empty('placeholder.bin');

// Custom file with specific content type
final pdfFile = TestFormFile(
name: 'document.pdf',
size: 2048,
contentType: 'application/pdf',
content: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), // PDF header
);

final adapter = MockViewAdapter(
files: {
'text': textFile,
'image': imageFile,
'empty': emptyFile,
'pdf': pdfFile,
},
);

final request = Request(adapter);

// Verify different content types
expect((await request.file('text'))!.contentType, equals('text/plain'));
expect((await request.file('image'))!.contentType, equals('image/jpeg'));
expect((await request.file('pdf'))!.contentType, equals('application/pdf'));
});
```

### Running Tests

```bash
# Run all tests
dart test

# Run specific test file
dart test test/request_test.dart

# Run with verbose output
dart test --verbose
```

## Architecture

The package follows a clean architecture with framework-agnostic views that work through adapters:

- **Views**: Framework-independent business logic
- **Adapters**: Bridge between views and specific frameworks
- **Mixins**: Composable functionality (context, forms, CRUD operations)

See [PACKAGE_RESTRUCTURE.md](PACKAGE_RESTRUCTURE.md) for detailed architecture documentation.
