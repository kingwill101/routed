import 'package:intl/intl.dart';

class Todo {
  Todo({
    required this.id,
    required this.title,
    required this.createdAt,
    this.notes,
    this.completed = false,
  });

  final int id;
  String title;
  String? notes;
  bool completed;
  final DateTime createdAt;

  Map<String, Object?> toMap({int? selectedId}) {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'completed': completed,
      'created_at': createdAt.toIso8601String(),
      'formatted_created_at': DateFormat.yMMMd().format(createdAt.toLocal()),
      'is_selected': selectedId == id,
    };
  }
}

class TodoRepository {
  TodoRepository._(this._todos, this._nextId);

  final List<Todo> _todos;
  int _nextId;

  factory TodoRepository.seed() {
    final now = DateTime.now();
    final seed = <Todo>[
      Todo(
        id: 1,
        title: 'Sketch landing page',
        notes: 'Rough draft for the marketing site hero',
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      Todo(
        id: 2,
        title: 'Wire up Turbo Streams',
        notes: 'Hook the todo list to routed_hotwire',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
      Todo(
        id: 3,
        title: 'Polish copy',
        notes: 'Review CTA wording with the team',
        createdAt: now.subtract(const Duration(minutes: 1)),
        completed: true,
      ),
    ];
    seed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TodoRepository._(seed, seed.length + 1);
  }

  List<Todo> all() {
    final copy = List<Todo>.from(_todos);
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  Todo? find(int id) {
    for (final todo in _todos) {
      if (todo.id == id) {
        return todo;
      }
    }
    return null;
  }

  Todo create({required String title, String? notes}) {
    final todo = Todo(
      id: _nextId++,
      title: title,
      notes: notes,
      createdAt: DateTime.now().toUtc(),
    );
    _todos.add(todo);
    return todo;
  }

  Todo? toggle(int id) {
    final todo = find(id);
    if (todo == null) return null;
    todo.completed = !todo.completed;
    return todo;
  }

  Todo? delete(int id) {
    Todo? removed;
    _todos.removeWhere((todo) {
      final shouldRemove = todo.id == id;
      if (shouldRemove) {
        removed = todo;
      }
      return shouldRemove;
    });
    return removed;
  }
}
