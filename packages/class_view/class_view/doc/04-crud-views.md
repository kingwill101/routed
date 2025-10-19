# CRUD Views

Class View provides a set of generic CRUD (Create, Read, Update, Delete) views that make it easy to implement common
operations. These views are designed to be simple to use while providing powerful functionality.

## Overview

The CRUD views are built on top of the base `View` class and provide a clean, framework-agnostic way to handle common
operations:

```dart
// Create a new object
class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> createObject(Map<String, dynamic> data) async {
    return await repository.create(data);
  }
}

// View a single object
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await repository.findById(id);
  }
}

// List objects with pagination
class PostListView extends ListView<Post> {
  @override
  Future<List<Post>> getObjectList() async {
    final page = getParam('page', defaultValue: '1');
    return await repository.findAll(page: int.parse(page));
  }
}

// Update an existing object
class PostUpdateView extends UpdateView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await repository.findById(id);
  }
  
  @override
  Future<Post> updateObject(Post object, Map<String, dynamic> data) async {
    return await repository.update(object.id, data);
  }
}

// Delete an object
class PostDeleteView extends DeleteView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await repository.findById(id);
  }
  
  @override
  Future<void> deleteObject(Post object) async {
    await repository.delete(object.id);
  }
}
```

## CreateView

The `CreateView` handles POST requests to create new objects:

```dart
class CreateView<T> extends View {
  // Required: Implement this method to create your object
  Future<T> createObject(Map<String, dynamic> data);
  
  // Optional: Override to customize validation
  Future<void> validateCreateData(Map<String, dynamic> data) async {}
  
  // Optional: Override to customize response
  Future<void> post() async {
    final data = await getJsonBody();
    await validateCreateData(data);
    final object = await createObject(data);
    sendJson(object.toJson());
  }
}
```

### Example

```dart
class UserCreateView extends CreateView<User> {
  @override
  Future<User> createObject(Map<String, dynamic> data) async {
    // Validate required fields
    if (!data.containsKey('email')) {
      throw HttpException.badRequest('Email is required');
    }
    
    // Create the user
    return await userRepository.create(data);
  }
  
  @override
  Future<void> validateCreateData(Map<String, dynamic> data) async {
    // Check if email is already taken
    final existing = await userRepository.findByEmail(data['email']);
    if (existing != null) {
      throw HttpException.badRequest('Email already taken');
    }
  }
}
```

## DetailView

The `DetailView` handles GET requests to retrieve a single object:

```dart
class DetailView<T> extends View {
  // Required: Implement this method to get your object
  Future<T?> getObject();
  
  // Optional: Override to customize response
  Future<void> get() async {
    final object = await getObject();
    if (object == null) throw HttpException.notFound();
    sendJson(object.toJson());
  }
}
```

### Example

```dart
class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await postRepository.findById(id);
  }
  
  @override
  Future<void> get() async {
    final post = await getObject();
    if (post == null) throw HttpException.notFound('Post not found');
    
    // Add related data
    final author = await userRepository.findById(post.authorId);
    final comments = await commentRepository.findByPostId(post.id);
    
    sendJson({
      'post': post.toJson(),
      'author': author?.toJson(),
      'comments': comments.map((c) => c.toJson()).toList(),
    });
  }
}
```

## ListView

The `ListView` handles GET requests to list objects with built-in pagination:

```dart
class ListView<T> extends View {
  // Required: Implement this method to get your object list
  Future<List<T>> getObjectList();
  
  // Optional: Override to customize pagination
  int get pageSize => 20;
  
  // Optional: Override to customize response
  Future<void> get() async {
    final page = int.parse(getParam('page', defaultValue: '1'));
    final objects = await getObjectList();
    
    sendJson({
      'objects': objects.map((o) => o.toJson()).toList(),
      'page': page,
      'page_size': pageSize,
    });
  }
}
```

### Example

```dart
class PostListView extends ListView<Post> {
  @override
  Future<List<Post>> getObjectList() async {
    final page = int.parse(getParam('page', defaultValue: '1'));
    final category = getParam('category');
    
    return await postRepository.findAll(
      page: page,
      pageSize: pageSize,
      category: category,
    );
  }
  
  @override
  int get pageSize => 10; // Override default page size
}
```

## UpdateView

The `UpdateView` handles PUT requests to update existing objects:

```dart
class UpdateView<T> extends View {
  // Required: Implement these methods
  Future<T?> getObject();
  Future<T> updateObject(T object, Map<String, dynamic> data);
  
  // Optional: Override to customize validation
  Future<void> validateUpdateData(T object, Map<String, dynamic> data) async {}
  
  // Optional: Override to customize response
  Future<void> put() async {
    final object = await getObject();
    if (object == null) throw HttpException.notFound();
    
    final data = await getJsonBody();
    await validateUpdateData(object, data);
    final updated = await updateObject(object, data);
    sendJson(updated.toJson());
  }
}
```

### Example

```dart
class UserUpdateView extends UpdateView<User> {
  @override
  Future<User?> getObject() async {
    final id = getParam('id');
    return await userRepository.findById(id);
  }
  
  @override
  Future<User> updateObject(User user, Map<String, dynamic> data) async {
    // Only allow updating certain fields
    final allowedFields = ['name', 'bio', 'avatar'];
    final filteredData = Map.fromEntries(
      data.entries.where((e) => allowedFields.contains(e.key))
    );
    
    return await userRepository.update(user.id, filteredData);
  }
  
  @override
  Future<void> validateUpdateData(User user, Map<String, dynamic> data) async {
    if (data.containsKey('email')) {
      final existing = await userRepository.findByEmail(data['email']);
      if (existing != null && existing.id != user.id) {
        throw HttpException.badRequest('Email already taken');
      }
    }
  }
}
```

## DeleteView

The `DeleteView` handles DELETE requests to remove objects:

```dart
class DeleteView<T> extends View {
  // Required: Implement these methods
  Future<T?> getObject();
  Future<void> deleteObject(T object);
  
  // Optional: Override to customize response
  Future<void> delete() async {
    final object = await getObject();
    if (object == null) throw HttpException.notFound();
    
    await deleteObject(object);
    sendJson({'status': 'success'});
  }
}
```

### Example

```dart
class PostDeleteView extends DeleteView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = getParam('id');
    return await postRepository.findById(id);
  }
  
  @override
  Future<void> deleteObject(Post post) async {
    // Delete related comments first
    await commentRepository.deleteByPostId(post.id);
    // Then delete the post
    await postRepository.delete(post.id);
  }
  
  @override
  Future<void> delete() async {
    final post = await getObject();
    if (post == null) throw HttpException.notFound('Post not found');
    
    // Check permissions
    if (!await canDeletePost(post)) {
      throw HttpException.forbidden('Cannot delete this post');
    }
    
    await deleteObject(post);
    sendJson({'status': 'success', 'message': 'Post deleted'});
  }
}
```

## Best Practices

1. **Keep Views Simple**: Focus on the core CRUD operation and delegate complex logic to services or repositories.

2. **Use Type Safety**: Always specify the generic type parameter for better type safety and IDE support.

3. **Handle Errors**: Use appropriate HTTP exceptions for different error cases.

4. **Validate Data**: Implement validation in the appropriate methods to ensure data integrity.

5. **Customize Responses**: Override the HTTP method handlers to customize responses when needed.

6. **Use Pagination**: Always implement pagination for list views to handle large datasets efficiently.

7. **Check Permissions**: Add permission checks in the appropriate lifecycle methods.

8. **Keep Framework Agnostic**: Avoid framework-specific code in your views.

## What's Next?

CRUD views become even more powerful when combined with other features:

- **[Mixins & Composition](05-mixins.md)** - Add authentication, caching, and more
- **[Forms Overview](07-forms-overview.md)** - Advanced form handling and validation
- **[Framework Integration](06-framework-integration.md)** - Deploy with your preferred framework

---

← [Basic Views](03-basic-views.md) | **Next: [Mixins & Composition](05-mixins.md)** → 