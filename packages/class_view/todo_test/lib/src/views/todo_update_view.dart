import 'package:class_view/class_view.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';

/// Update view for todos
///
/// Demonstrates clean UpdateView implementation with validation following Django-like patterns.
class TodoUpdateView extends UpdateView<Todo> {
  final TodoRepository _repository;

  TodoUpdateView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  List<String> get allowedMethods => ['GET', 'PUT', 'PATCH'];

  @override
  String get successUrl => '/todos';

  @override
  Future<Todo?> getObject() async {
    final id = await getParam('id');
    if (id == null) return null;
    return await _repository.findById(id);
  }

  @override
  Future<Todo> performUpdate(Todo object, Map<String, dynamic> data) async {
    // Validate fields if provided
    final title = data['title'] as String?;
    final description = data['description'] as String?;
    final completed = data['completed'] as bool?;

    if (title != null && title.trim().isEmpty) {
      throw ArgumentError('Title cannot be empty');
    }

    if (title != null && title.length > 200) {
      throw ArgumentError('Title cannot be longer than 200 characters');
    }

    if (description != null && description.trim().isEmpty) {
      throw ArgumentError('Description cannot be empty');
    }

    if (description != null && description.length > 1000) {
      throw ArgumentError('Description cannot be longer than 1000 characters');
    }

    // Update the todo
    final updated = object.copyWith(
      title: title?.trim(),
      description: description?.trim(),
      completed: completed,
      updatedAt: DateTime.now(),
    );

    return await _repository.update(object.id, updated);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final todo = object as Todo;
    sendJson({
      'todo': todo.toJson(),
      'message': 'Todo updated successfully',
      'success_url': successUrl,
    });
  }

  @override
  Future<void> onFailure(Object error, [dynamic object]) async {
    int statusCode = 400;
    String message = error.toString();

    if (error is HttpException) {
      statusCode = error.statusCode;
      message = error.message;
    } else if (error is ArgumentError) {
      statusCode = 400;
      message = error.message;
    } else {
      statusCode = 500;
      message = 'An unexpected error occurred while updating the todo';
    }

    sendJson({'error': message, 'success': false}, statusCode: statusCode);
  }

  @override
  Future<void> get() async {
    final todo = await getObjectOr404();

    sendJson({
      'todo': todo.toJson(),
      'message': 'PUT/PATCH to this endpoint to update the todo',
      'allowed_fields': ['title', 'description', 'completed'],
      'validation': {
        'title': 'Optional, max 200 characters',
        'description': 'Optional, max 1000 characters',
        'completed': 'Optional boolean',
      },
    });
  }
}
