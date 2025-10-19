# SimpleBlog - Complete Feature Showcase

This document provides a comprehensive overview of all class_view features demonstrated in the SimpleBlog application.

## 📚 Table of Contents

1. [CRUD Views](#crud-views)
2. [Form Handling](#form-handling)
3. [Mixins](#mixins)
4. [Search & Filtering](#search--filtering)
5. [Error Handling](#error-handling)
6. [Redirects](#redirects)
7. [Nested Resources](#nested-resources)
8. [Advanced Features](#advanced-features)

---

## 🔧 CRUD Views

### ListView - Paginated List Display

**File:** `lib/src/views/api/post_list_view.dart`

Demonstrates:

- ✅ Automatic pagination
- ✅ Search functionality
- ✅ Result counting
- ✅ Extra context injection

```dart
class PostListView extends ListView<Post> {
  @override
  int get paginate => 10;
  
  @override
  Future<({List<Post> items, int total})> getObjectList({...}) async {
    return await repository.findAll(page, pageSize);
  }
}
```

**Usage:**

```bash
GET /api/posts?page=1&page_size=10
GET /api/posts?search=dart
```

### DetailView - Single Object Display

**File:** `lib/src/views/api/post_detail_view.dart`

Demonstrates:

- ✅ URL parameter extraction
- ✅ 404 handling (null = not found)
- ✅ Object serialization

```dart
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final slug = await getParam('slug');
    return await repository.findBySlug(slug);
  }
}
```

**Usage:**

```bash
GET /api/posts/my-awesome-post
```

### CreateView - Object Creation

**File:** `lib/src/views/api/post_create_view.dart`

Demonstrates:

- ✅ Form data validation
- ✅ Success/failure callbacks
- ✅ Custom error messages
- ✅ JSON response formatting

```dart
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    // Validate
    if (title.isEmpty) throw ArgumentError('Title required');
    
    // Create
    return await repository.create(Post.fromFormData(data));
  }
  
  @override
  Future<void> onSuccess([dynamic object]) async {
    sendJson({'success': true, 'post': object.toJson()}, statusCode: 201);
  }
}
```

**Usage:**

```bash
POST /api/posts
Content-Type: application/json

{"title": "New Post", "content": "..."}
```

### UpdateView - Object Modification

**File:** `lib/src/views/api/post_update_view.dart`

Demonstrates:

- ✅ Loading existing object
- ✅ Partial updates
- ✅ Validation on update
- ✅ Optimistic locking patterns

```dart
class PostUpdateView extends UpdateView<Post> {
  @override
  Future<Post?> getObject() async {...}
  
  @override
  Future<Post> performUpdate(Post object, Map<String, dynamic> data) async {
    return await repository.update(object.id, data);
  }
}
```

**Usage:**

```bash
PUT /api/posts/123
Content-Type: application/json

{"title": "Updated Title"}
```

### DeleteView - Safe Object Deletion

**File:** `lib/src/views/api/post_delete_view.dart`

Demonstrates:

- ✅ Confirmation patterns
- ✅ Cascade delete considerations
- ✅ Soft delete vs hard delete
- ✅ Authorization checks

```dart
class PostDeleteView extends DeleteView<Post> {
  @override
  Future<void> performDelete(Post object) async {
    await repository.delete(object.id);
  }
}
```

**Usage:**

```bash
DELETE /api/posts/123
```

---

## 📝 Form Handling

### BaseFormView - HTML Form Rendering

**File:** `lib/src/views/web/post_form_view.dart`

Demonstrates:

- ✅ GET: Display form
- ✅ POST: Process submission
- ✅ Form validation with error display
- ✅ Template rendering

```dart
class WebPostFormView extends BaseFormView {
  @override
  Form getForm([Map<String, dynamic>? data]) {
    return PostForm(data: data, isBound: data != null);
  }
  
  @override
  Future<void> formValid(Form form) async {
    // Process valid form
  }
  
  @override
  Future<void> formInvalid(Form form) async {
    // Re-render with errors
  }
}
```

### Form Fields & Validation

**File:** Various form definitions

Demonstrates:

- ✅ CharField, EmailField, URLField
- ✅ TextAreaField for long content
- ✅ BooleanField for checkboxes
- ✅ ChoiceField for dropdowns
- ✅ Custom validators
- ✅ Error message customization

```dart
class PostForm extends Form {
  PostForm({Map<String, dynamic>? data}) : super(
    data: data ?? {},
    fields: {
      'title': CharField<String>(
        required: true,
        maxLength: 200,
        validators: [CustomValidator()],
      ),
      'content': TextAreaField(),
      'isPublished': BooleanField(),
    },
  );
}
```

---

## 🧩 Mixins

### ContextMixin - Data Context Injection

**File:** Throughout the codebase

Demonstrates:

- ✅ Adding extra template variables
- ✅ Reusable data providers
- ✅ Dynamic context generation

```dart
class HomeView extends View with ContextMixin {
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'recent_posts': await repository.findRecent(),
      'stats': await getStatistics(),
    };
  }
}
```

### Custom Application Mixins

**File:** `lib/src/views/mixins/custom_mixins.dart`

#### CachingMixin

```dart
class CachedPostListView extends ListView<Post> with CachingMixin {
  @override
  int get cacheDuration => 300; // 5 minutes
}
```

#### LoginRequiredMixin

```dart
class ProtectedView extends View with LoginRequiredMixin {
  @override
  Future<void> dispatch() async {
    await checkAuthentication();
    await super.dispatch();
  }
}
```

#### PermissionRequiredMixin

```dart
class AdminView extends View with PermissionRequiredMixin {
  @override
  List<String> get requiredPermissions => ['admin.write'];
}
```

#### LoggingMixin

```dart
class LoggedView extends View with LoggingMixin {
  @override
  Future<void> get() async {
    await logRequest();
    // ... handle request
    await logResponse(200);
  }
}
```

#### RateLimitMixin

```dart
class RateLimitedView extends View with RateLimitMixin {
  @override
  int get maxRequests => 100;
  
  @override
  int get windowSeconds => 60;
}
```

---

## 🔍 Search & Filtering

### Advanced Search View

**File:** `lib/src/views/api/post_search_view.dart`

Demonstrates:

- ✅ Multiple query parameters
- ✅ Combined filters (search + tags + author)
- ✅ Dynamic ordering (by date, title, author)
- ✅ Faceted search results
- ✅ Search result highlighting

**Features:**

```bash
# Text search
GET /api/search?q=class-view

# Filter by tags
GET /api/search?tags=dart,web

# Filter by author
GET /api/search?author=John

# Combined filters
GET /api/search?q=tutorial&tags=dart&status=published

# Custom ordering
GET /api/search?order_by=title&order_dir=asc

# Faceted results
GET /api/search?q=dart
# Returns counts by status, tags, etc.
```

### List Filtering & Ordering

```dart
class PostSearchView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({...}) async {
    final query = await getParam('q');
    final tags = await getParam('tags');
    final orderBy = await getParam('order_by') ?? 'created_at';
    
    return await repository.search(
      query: query,
      tags: tags?.split(','),
      orderBy: orderBy,
    );
  }
  
  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'facets': await getFacets(), // Counts by category
      'order_options': [...],
    };
  }
}
```

---

## ⚠️ Error Handling

### Custom Error Views

**File:** `lib/src/views/api/error_views.dart`

#### 404 Not Found

```dart
class NotFoundView extends View {
  @override
  Future<void> get() async {
    sendJson({
      'error': 'Not Found',
      'path': await getParam('path'),
      'suggestions': getSuggestions(),
    }, statusCode: 404);
  }
}
```

#### 500 Server Error

```dart
class ServerErrorView extends View {
  @override
  Future<void> get() async {
    final isDevelopment = true;
    sendJson({
      'error': 'Internal Server Error',
      'message': isDevelopment ? errorDetails : 'Try again later',
    }, statusCode: 500);
  }
}
```

#### 403 Forbidden

```dart
class ForbiddenView extends View {
  @override
  Future<void> get() async {
    sendJson({
      'error': 'Forbidden',
      'message': 'Permission denied',
    }, statusCode: 403);
  }
}
```

#### 422 Validation Error

```dart
class ValidationErrorView extends View {
  @override
  Future<void> post() async {
    sendJson({
      'error': 'Validation Error',
      'errors': {
        'title': ['Title is required'],
        'email': ['Invalid email format'],
      },
    }, statusCode: 422);
  }
}
```

---

## 🔀 Redirects

**File:** `lib/src/views/api/redirect_views.dart`

### Permanent Redirect (301)

```dart
class LegacyPostRedirectView extends RedirectView {
  @override
  bool get permanent => true;
  
  @override
  Future<String> getRedirectUrl() async {
    final oldPath = await getParam('path');
    return '/posts/$oldPath';
  }
}
```

### Temporary Redirect (302)

```dart
class PostIdRedirectView extends RedirectView {
  @override
  bool get permanent => false;
  
  @override
  Future<String> getRedirectUrl() async {
    final id = await getParam('id');
    final post = await repository.findById(id);
    return '/posts/${post.slug}';
  }
}
```

### Conditional Redirects

```dart
class ConditionalRedirectView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    return await isAuthenticated() 
        ? '/dashboard' 
        : '/login';
  }
}
```

### Query Parameter Preservation

```dart
class QueryPreservingRedirectView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    final params = await getParams();
    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '/posts?$queryString';
  }
}
```

### Smart Redirects

```dart
class SmartRedirectView extends RedirectView {
  @override
  Future<String> getRedirectUrl() async {
    final returnTo = await getParam('return_to');
    final referrer = await getHeader('Referer');
    
    return returnTo ?? referrer ?? '/';
  }
}
```

---

## 🪆 Nested Resources

### Parent-Child Relationships

**Files:**

- `lib/src/views/api/comment_create_view.dart`
- `lib/src/views/api/comment_list_view.dart`
- `lib/src/views/api/comment_delete_view.dart`

#### Creating Nested Resources

```dart
class CommentCreateView extends CreateView<Comment> {
  @override
  Future<Comment> performCreate(Map<String, dynamic> data) async {
    // Validate parent exists
    final postId = data['postId'];
    final post = await postRepo.findById(postId);
    if (post == null) {
      throw HttpException.notFound('Post not found');
    }
    
    // Create comment
    return await commentRepo.create(Comment.fromFormData(data));
  }
}
```

**Usage:**

```bash
POST /api/posts/123/comments
{"content": "Great post!", "author": "Alice"}
```

#### Listing Nested Resources

```dart
class CommentListView extends ListView<Comment> {
  @override
  Future<({List<Comment> items, int total})> getObjectList({...}) async {
    final postId = await getParam('postId');
    
    if (postId != null) {
      return await commentRepo.findByPostIdPaginated(postId, page, pageSize);
    }
    
    // Or list all comments (admin view)
    return await commentRepo.findAll(page, pageSize);
  }
}
```

**Usage:**

```bash
GET /api/posts/123/comments
GET /api/comments  # All comments
```

---

## 🚀 Advanced Features

### ModelFormView - Model-Bound Forms

**File:** `lib/src/views/web/post_form_view.dart`

Demonstrates:

- ✅ Auto-populating forms from model instances
- ✅ Field mapping
- ✅ Model validation

```dart
class WebPostEditView extends ModelFormView<Post> {
  @override
  Future<Post?> getObject() async {...}
  
  @override
  Form getForm([Map<String, dynamic>? data]) {
    return PostForm(data: data ?? object?.toJson());
  }
}
```

### Template Rendering

Demonstrates:

- ✅ Template inheritance
- ✅ Custom tags and filters
- ✅ Context processors
- ✅ Multiple template engines

### Content Negotiation

Demonstrates:

- ✅ Same view serves HTML or JSON
- ✅ Accept header detection
- ✅ Format query parameter

```dart
class FlexibleView extends View {
  @override
  Future<void> get() async {
    final accept = await getHeader('Accept');
    
    if (accept?.contains('application/json') ?? false) {
      sendJson(data);
    } else {
      renderTemplate('view.html', data);
    }
  }
}
```

### Batch Operations

Demonstrates:

- ✅ Bulk updates
- ✅ Mass deletion
- ✅ Transaction handling

### API Versioning

Demonstrates:

- ✅ URL-based versioning (`/api/v1/posts`)
- ✅ Header-based versioning
- ✅ Backward compatibility

---

## 📊 Complete Feature Matrix

| Feature            | Location                    | Status |
|--------------------|-----------------------------|--------|
| ListView           | `api/post_list_view.dart`   | ✅      |
| DetailView         | `api/post_detail_view.dart` | ✅      |
| CreateView         | `api/post_create_view.dart` | ✅      |
| UpdateView         | `api/post_update_view.dart` | ✅      |
| DeleteView         | `api/post_delete_view.dart` | ✅      |
| BaseFormView       | `web/post_form_view.dart`   | ✅      |
| ModelFormView      | `web/post_form_view.dart`   | ✅      |
| RedirectView       | `api/redirect_views.dart`   | ✅      |
| Error Views        | `api/error_views.dart`      | ✅      |
| Search & Filter    | `api/post_search_view.dart` | ✅      |
| Nested Resources   | `api/comment_*_view.dart`   | ✅      |
| Custom Mixins      | `mixins/custom_mixins.dart` | ✅      |
| Pagination         | All list views              | ✅      |
| Form Validation    | All form views              | ✅      |
| Template Rendering | Web views                   | ✅      |
| JSON API           | API views                   | ✅      |
| Caching            | CachingMixin                | ✅      |
| Authentication     | LoginRequiredMixin          | ✅      |
| Permissions        | PermissionRequiredMixin     | ✅      |
| Rate Limiting      | RateLimitMixin              | ✅      |
| Logging            | LoggingMixin                | ✅      |

---

## 🎯 Learning Path

**Beginners:** Start with CRUD views

1. ListView → DetailView
2. CreateView → UpdateView → DeleteView
3. Form handling basics

**Intermediate:** Explore mixins and advanced features

1. ContextMixin for data injection
2. Search and filtering
3. Nested resources

**Advanced:** Custom patterns

1. Custom mixins
2. Error handling strategies
3. Performance optimization
4. Content negotiation

---

## 📚 Additional Resources

- [class_view Documentation](../class_view/README.md)
- [Django CBV Documentation](https://docs.djangoproject.com/en/stable/topics/class-based-views/)
- [REST API Best Practices](https://restfulapi.net/)

---

**SimpleBlog** - Your comprehensive class_view reference! 🚀
