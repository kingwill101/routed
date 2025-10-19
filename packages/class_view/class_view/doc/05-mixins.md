# Mixins

> **Note**: While Class View provides built-in view classes for common operations, mixins are available for creating
> custom functionality that isn't directly supported by the standard views.

## Overview

Mixins in Class View provide reusable functionality that can be composed to create custom views. While we encourage
using the built-in view classes for common operations, mixins are available when you need to create something more
specialized.

## When to Use Mixins

1. **Custom Functionality**: When you need functionality not provided by the built-in views
2. **Specialized Views**: For creating views with unique requirements
3. **Reusable Patterns**: When you want to share functionality across multiple custom views
4. **Framework Integration**: For creating framework-specific adapters or handlers

## Built-in Views vs Custom Mixins

```dart
// ✅ Use built-in views for standard operations
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await repository.findById(id);
  }
}

// ✅ Use mixins for custom functionality
class AnalyticsDashboardView extends View 
    with ContextMixin, AuthRequiredMixin, CacheMixin {
  
  @override
  Future<void> get() async {
    final data = await getAnalyticsData();
    sendJson(data);
  }
}
```

## Available Mixins

### Core Mixins

```dart
// Context handling
mixin ContextMixin on ViewMixin {
  Map<String, dynamic> get extraContext => {};
  Future<Map<String, dynamic>> getContextData() async {
    return {'view': this, ...await getExtraContext()};
  }
}

// Single object operations
mixin SingleObjectMixin<T> on ContextMixin {
  Future<T?> getObject();
  Future<T> getObjectOr404() async {
    final object = await getObject();
    if (object == null) throw HttpException.notFound();
    return object;
  }
}

// List operations with pagination
mixin ListObjectMixin<T> on ContextMixin {
  Future<List<T>> getObjectList();
  int get pageSize => 20;
}
```

### Custom Mixin Examples

```dart
// Authentication mixin
mixin AuthRequiredMixin on ViewMixin {
  @override
  Future<void> setup() async {
    await super.setup();
    if (!isAuthenticated()) {
      throw HttpException.unauthorized();
    }
  }
  
  bool isAuthenticated() {
    final token = getHeader('Authorization');
    return token != null && validateToken(token);
  }
}

// Caching mixin
mixin CacheMixin on ViewMixin {
  Duration get cacheTimeout => Duration(minutes: 5);
  
  @override
  Future<void> get() async {
    final cacheKey = getCacheKey();
    final cached = await cache.get(cacheKey);
    
    if (cached != null) {
      sendJson(cached);
      return;
    }
    
    await super.get();
    // Cache the response
  }
}

// Rate limiting mixin
mixin RateLimitMixin on ViewMixin {
  int get requestsPerMinute => 60;
  
  @override
  Future<void> setup() async {
    await super.setup();
    if (!await checkRateLimit()) {
      throw HttpException.tooManyRequests();
    }
  }
}
```

## Creating Custom Mixins

When creating custom mixins, follow these guidelines:

1. **Single Responsibility**: Each mixin should do one thing well
2. **Clear Dependencies**: Document which mixins your mixin depends on
3. **Consistent Patterns**: Follow the established patterns for method names and behavior
4. **Error Handling**: Use appropriate HTTP exceptions for errors
5. **Async Support**: Make all methods properly asynchronous

Example of a custom mixin:

```dart
mixin SearchableMixin<T> on ContextMixin {
  Future<List<T>> search(String query, {int page = 1, int pageSize = 20});
  
  @override
  Future<void> get() async {
    final query = getParam('q') ?? '';
    final results = await search(query);
    sendJson({
      'results': results.map((r) => r.toJson()).toList(),
      'query': query,
    });
  }
}

// Usage
class ProductSearchView extends View 
    with ContextMixin, SearchableMixin<Product> {
  
  @override
  Future<List<Product>> search(String query, {int page = 1, int pageSize = 20}) async {
    return await productRepository.search(
      query: query,
      page: page,
      pageSize: pageSize,
    );
  }
}
```

## Best Practices

1. **Use Built-in Views**: Prefer built-in views for standard operations
2. **Document Custom Mixins**: Clearly document the purpose and usage of custom mixins
3. **Test Thoroughly**: Test mixins in isolation and in combination
4. **Keep It Simple**: Avoid complex mixin compositions
5. **Follow Patterns**: Use consistent patterns across your mixins

## What's Next?

- Learn about [Framework Integration](06-framework-integration.md) to connect your views to web frameworks
- Explore [Form Handling](07-forms-overview.md) for processing user input
- See [Templates](11-templates.md) for rendering views with templates

---

← [CRUD Views](04-crud-views.md) | **Next: [Framework Integration](06-framework-integration.md)** → 