# SimpleBlog

A comprehensive demonstration of the **class_view** framework for Dart web development, showcasing Django-style
class-based views with Shelf integration.

## 🎯 What This Demonstrates

This SimpleBlog application showcases **every major feature** of the class_view framework:

### ✅ Complete CRUD Operations

- **ListView** - Paginated post listings with search
- **DetailView** - Individual post display
- **CreateView** - New post creation with validation
- **UpdateView** - Post editing with form handling
- **DeleteView** - Safe post deletion with confirmation

### 🏗️ Django-Style Architecture

- Clean, composable views using mixins
- Framework-agnostic design with Shelf adapter
- Type-safe form handling and validation
- RESTful API endpoints with JSON responses

### 🔍 Advanced Features

- **Search & Pagination** - Built-in search across posts
- **Form Validation** - Robust server-side validation
- **Error Handling** - Comprehensive error management
- **Content Negotiation** - Same views serve HTML/JSON

## 🚀 Quick Start

### 1. Install Dependencies

```bash
dart pub get
```

### 2. Run the Server

```bash
dart run bin/simple_blog.dart
```

### 3. Open Your Browser

Visit [http://localhost:8080](http://localhost:8080) to see the demo interface.

## 📚 API Endpoints

### Posts API

```
GET    /api/posts           # List all posts (with pagination/search)
POST   /api/posts           # Create a new post  
GET    /api/posts/{slug}    # Get specific post by slug
PUT    /api/posts/{id}      # Update existing post
DELETE /api/posts/{id}      # Delete post
```

### Widget Showcase 🎨

**Interactive demonstration of ALL form field types!**

#### Web Interface (Beautiful UI)

```
GET    /widgets             # Interactive form showcase
POST   /widgets             # Test validation with visual feedback
```

#### JSON API

```
GET    /api/widgets         # Field catalog (JSON)
POST   /api/widgets         # Validation testing (JSON)
```

Perfect for learning, testing, and reference! See [WEB_WIDGET_SHOWCASE.md](WEB_WIDGET_SHOWCASE.md) for full
documentation.

### Web Interface

```
GET    /                    # Home dashboard
GET    /posts               # Browse posts (web interface)
GET    /posts/new           # New post form
GET    /posts/{slug}        # View post (web interface)
```

## 🧪 Try It Out

### List Posts

```bash
curl http://localhost:8080/api/posts
```

### Get Specific Post

```bash
curl http://localhost:8080/api/posts/welcome-to-simpleblog
```

### Create New Post

```bash
curl -X POST http://localhost:8080/api/posts \
  -H "Content-Type: application/json" \
  -d '{
    "title": "My Awesome Post",
    "content": "# Hello World\n\nThis is my first post!",
    "author": "John Doe",
    "isPublished": true,
    "tags": "demo,tutorial"
  }'
```

### Search Posts

```bash
curl "http://localhost:8080/api/posts?search=class-view"
```

### Test Widget Showcase

#### Via Web Browser

```bash
# Visit the interactive showcase
open http://localhost:8080/widgets
```

#### Via API

```bash
# View all available fields (JSON)
curl http://localhost:8080/api/widgets

# Test form validation (JSON)
curl -X POST http://localhost:8080/api/widgets \
  -H "Content-Type: application/json" \
  -d '{
    "text_required": "Hello World",
    "email": "user@example.com",
    "checkbox": true,
    "choice_single": "option1",
    "integer_range": 50
  }'
```

### Update Post

```bash
curl -X PUT http://localhost:8080/api/posts/{post-id} \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Updated Title",
    "content": "Updated content here...",
    "author": "Jane Doe",
    "isPublished": false
  }'
```

## 🏗️ Architecture Overview

### Models (`lib/src/models/`)

- **Post** - Blog post domain model with validation
- **Comment** - Comment system (structure for future expansion)

### Views (`lib/src/views/`)

- **HomeView** - Dashboard with statistics
- **PostListView** - Paginated list with search (extends `ListView<Post>`)
- **PostDetailView** - Individual post display (extends `DetailView<Post>`)
- **PostCreateView** - New post creation (extends `CreateView<Post>`)
- **PostUpdateView** - Post editing (extends `UpdateView<Post>`)
- **PostDeleteView** - Post deletion (extends `DeleteView<Post>`)

### Repository (`lib/src/repositories/`)

- **PostRepository** - In-memory data storage with CRUD operations

### Server (`lib/src/server.dart`)

- Shelf integration using `shelf_class_view`
- Middleware for CORS, logging, and error handling
- Route registration with clean view mapping

## 🎨 Key Features Demonstrated

### 1. **Clean View Syntax**

```dart
class PostListView extends ListView<Post> {
  @override
  int get paginate => 5;
  
  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    return await repository.findWithPagination(
      page: page,
      pageSize: pageSize,
      search: getParam('search'),
    );
  }
}
```

### 2. **Mixin Composition**

```dart
class HomeView extends View with ContextMixin {
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'recent_posts': await repository.findAll(),
      'features': [...],
    };
  }
}
```

### 3. **Form Validation**

```dart
@override
Future<Post> createObject(Map<String, dynamic> data) async {
  // Validate required fields
  if (title == null || title.trim().isEmpty) {
    throw ArgumentError('Title is required');
  }
  
  // Create and save
  return await repository.create(Post.fromFormData(data));
}
```

### 4. **Error Handling**

```dart
@override
Future<void> onFailure(Object error, [dynamic data]) async {
  final statusCode = error is ArgumentError ? 400 : 500;
  sendJson({
    'error': error.toString(),
    'success': false,
  }, statusCode: statusCode);
}
```

### 5. **Route Registration**

```dart
// Clean route registration with shelf_class_view
router.getView('/posts', () => PostListView());
router.postView('/posts/create', () => PostCreateView());
router.putView('/posts/<id>/update', () => PostUpdateView());
```

## 📖 Code Structure

```
simple_blog/
├── lib/
│   ├── src/
│   │   ├── models/          # Domain models
│   │   ├── repositories/    # Data layer  
│   │   ├── views/          # Class-based views
│   │   └── server.dart     # Shelf server setup
│   └── simple_blog.dart    # Library exports
├── web/
│   └── index.html          # Demo interface
├── bin/
│   └── simple_blog.dart    # Server entry point
└── README.md
```

## 🎓 Learning Goals

This project demonstrates:

1. **View Inheritance** - How to extend base views for specific functionality
2. **Mixin Composition** - Building features through composable mixins
3. **Form Handling** - Type-safe form processing and validation
4. **Error Management** - Comprehensive error handling patterns
5. **Content Negotiation** - Single views serving multiple formats
6. **Route Organization** - Clean URL structure with meaningful endpoints
7. **Framework Integration** - Seamless Shelf integration patterns

## 🔧 Extending the Demo

Want to add more features? Here are some ideas:

- **Comments System** - Implement the Comment model with CRUD operations
- **User Authentication** - Add login/logout with session management
- **File Uploads** - Extend CreateView/UpdateView with file handling
- **Template Rendering** - Add Liquid template integration for HTML responses
- **Database Integration** - Replace in-memory storage with Drift database
- **Testing** - Add comprehensive test suite for all views

## 📚 Related Documentation

- [class_view Documentation](../class_view/README.md)
- [shelf_class_view Integration](../shelf_class_view/README.md)
- [Django Class-Based Views](https://docs.djangoproject.com/en/stable/topics/class-based-views/) (inspiration)

## 🤝 Contributing

This is a demonstration project, but feel free to:

- Report issues with the examples
- Suggest improvements to the demos
- Add more comprehensive test cases
- Extend with additional features

---

**SimpleBlog** - Showcasing the power and elegance of class-based views in Dart! 🚀 