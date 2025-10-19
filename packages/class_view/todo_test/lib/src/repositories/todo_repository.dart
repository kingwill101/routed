import '../models/todo.dart';

/// In-memory Todo repository for testing
///
/// This provides a simple, thread-safe in-memory storage for todos
/// that can be used across different adapter tests.
class TodoRepository {
  final Map<String, Todo> _todos = {};

  /// Get all todos with optional pagination
  Future<({List<Todo> items, int total})> findAll({
    int page = 1,
    int pageSize = 10,
    bool? completed,
  }) async {
    var allTodos = _todos.values.toList();

    // Filter by completion status if specified
    if (completed != null) {
      allTodos = allTodos.where((todo) => todo.completed == completed).toList();
    }

    // Sort by creation date (newest first)
    allTodos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final total = allTodos.length;
    final startIndex = (page - 1) * pageSize;
    final endIndex = (startIndex + pageSize).clamp(0, total);

    final items = startIndex < total
        ? allTodos.sublist(startIndex, endIndex)
        : <Todo>[];

    return (items: items, total: total);
  }

  /// Find a todo by ID
  Future<Todo?> findById(String id) async {
    return _todos[id];
  }

  /// Create a new todo
  Future<Todo> create(Todo todo) async {
    if (_todos.containsKey(todo.id)) {
      throw ArgumentError('Todo with ID ${todo.id} already exists');
    }

    _todos[todo.id] = todo;
    return todo;
  }

  /// Update an existing todo
  Future<Todo> update(String id, Todo updatedTodo) async {
    if (!_todos.containsKey(id)) {
      throw ArgumentError('Todo with ID $id not found');
    }

    final todo = updatedTodo.copyWith(updatedAt: DateTime.now());
    _todos[id] = todo;
    return todo;
  }

  /// Delete a todo
  Future<void> delete(String id) async {
    if (!_todos.containsKey(id)) {
      throw ArgumentError('Todo with ID $id not found');
    }

    _todos.remove(id);
  }

  /// Mark a todo as completed
  Future<Todo> markCompleted(String id) async {
    final todo = _todos[id];
    if (todo == null) {
      throw ArgumentError('Todo with ID $id not found');
    }

    final updated = todo.copyWith(completed: true, updatedAt: DateTime.now());
    _todos[id] = updated;
    return updated;
  }

  /// Mark a todo as incomplete
  Future<Todo> markIncomplete(String id) async {
    final todo = _todos[id];
    if (todo == null) {
      throw ArgumentError('Todo with ID $id not found');
    }

    final updated = todo.copyWith(completed: false, updatedAt: DateTime.now());
    _todos[id] = updated;
    return updated;
  }

  /// Get count of todos by status
  Future<Map<String, int>> getStats() async {
    final all = _todos.values.toList();
    final completed = all.where((todo) => todo.completed).length;
    final pending = all.length - completed;

    return {'total': all.length, 'completed': completed, 'pending': pending};
  }

  /// Clear all todos (useful for testing)
  Future<void> clear() async {
    _todos.clear();
  }

  /// Seed with sample data for testing
  Future<void> seed() async {
    await clear();

    final sampleTodos = [
      Todo.create(
        title: 'Learn Dart',
        description: 'Study Dart programming language fundamentals',
        completed: true,
      ),
      Todo.create(
        title: 'Build class_view package',
        description: 'Create Django-inspired class-based views for Dart',
        completed: false,
      ),
      Todo.create(
        title: 'Write comprehensive tests',
        description: 'Ensure the package works with different adapters',
        completed: false,
      ),
      Todo.create(
        title: 'Document the API',
        description: 'Write clear documentation and examples',
        completed: false,
      ),
      Todo.create(
        title: 'Publish to pub.dev',
        description: 'Make the package available to the Dart community',
        completed: false,
      ),
    ];

    for (final todo in sampleTodos) {
      await create(todo);
    }
  }

  /// Get todos by search term (title or description)
  Future<List<Todo>> search(String query) async {
    if (query.isEmpty) return [];

    final lowercaseQuery = query.toLowerCase();
    return _todos.values
        .where(
          (todo) =>
              todo.title.toLowerCase().contains(lowercaseQuery) ||
              todo.description.toLowerCase().contains(lowercaseQuery),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
