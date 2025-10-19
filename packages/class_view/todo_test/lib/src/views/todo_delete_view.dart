import 'package:class_view/class_view.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';

/// Delete view for todos
///
/// Demonstrates clean DeleteView implementation following Django-like patterns.
class TodoDeleteView extends DeleteView<Todo> {
  final TodoRepository _repository;

  TodoDeleteView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  List<String> get allowedMethods => ['GET', 'DELETE'];

  @override
  String get successUrl => '/todos';

  @override
  Future<Todo?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await _repository.findById(id);
  }

  @override
  Future<void> performDelete(Todo object) async {
    await _repository.delete(object.id);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final todo = object as Todo;
    sendJson({
      'message': 'Todo deleted successfully',
      'deleted_todo': todo.toJson(),
      'success_url': successUrl,
    });
  }

  @override
  Future<void> onFailure(Object error, [dynamic object]) async {
    int statusCode = 500;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    } else if (error is ArgumentError) {
      statusCode = 404;
      message = error.message;
    } else {
      statusCode = 500;
      message = 'An unexpected error occurred while deleting the todo';
    }

    sendJson({'error': message, 'success': false}, statusCode: statusCode);
  }

  @override
  Future<void> get() async {
    final todo = await getObjectOr404();

    sendJson({
      'todo': todo.toJson(),
      'message': 'DELETE to this endpoint to delete the todo',
      'warning': 'This action cannot be undone',
    });
  }
}
