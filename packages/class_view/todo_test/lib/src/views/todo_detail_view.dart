import 'package:class_view/class_view.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';

/// Detail view for a single todo
///
/// Demonstrates clean DetailView implementation following Django-like patterns.
class TodoDetailView extends DetailView<Todo> {
  final TodoRepository _repository;

  TodoDetailView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  Future<Todo?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await _repository.findById(id);
  }

  @override
  String get contextObjectName => 'todo';
}

/// Toggle completion status view
///
/// Demonstrates a custom action view for toggling todo completion following Django-like patterns.
class TodoToggleView extends View with ContextMixin, SingleObjectMixin<Todo> {
  final TodoRepository _repository;

  TodoToggleView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  List<String> get allowedMethods => ['POST', 'PATCH'];

  @override
  Future<Todo?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await _repository.findById(id);
  }

  @override
  Future<void> post() async {
    await _toggleCompletion();
  }

  @override
  Future<void> patch() async {
    await _toggleCompletion();
  }

  Future<void> _toggleCompletion() async {
    final todo = await getObjectOr404();

    final updated = todo.completed
        ? await _repository.markIncomplete(todo.id)
        : await _repository.markCompleted(todo.id);

    sendJson({
      'todo': updated.toJson(),
      'message':
          'Todo ${updated.completed ? 'completed' : 'marked as pending'}',
      'action': updated.completed ? 'completed' : 'uncompleted',
    });
  }
}
