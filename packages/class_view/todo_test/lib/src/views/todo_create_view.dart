import 'package:class_view/class_view.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';

/// Create view for todos
///
/// Demonstrates clean CreateView implementation with validation following Django-like patterns.
class TodoCreateView extends CreateView<Todo> {
  final TodoRepository _repository;

  TodoCreateView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  String get successUrl => '/todos';

  @override
  Future<Todo> performCreate(Map<String, dynamic> data) async {
    // Validate required fields
    final title = data['title'] as String?;
    final description = data['description'] as String?;

    if (title == null || title.trim().isEmpty) {
      throw ArgumentError('Title is required and cannot be empty');
    }

    final trimmedTitle = title.trim();
    if (trimmedTitle.length > 200) {
      throw ArgumentError('Title cannot be longer than 200 characters');
    }

    if (description == null || description.trim().isEmpty) {
      throw ArgumentError('Description is required and cannot be empty');
    }

    final trimmedDescription = description.trim();
    if (trimmedDescription.length > 1000) {
      throw ArgumentError('Description cannot be longer than 1000 characters');
    }

    // Create the todo
    final todo = Todo.create(
      title: trimmedTitle,
      description: trimmedDescription,
      completed: data['completed'] as bool? ?? false,
    );

    return await _repository.create(todo);
  }

  @override
  Future<void> onSuccess([dynamic object]) async {
    final todo = object as Todo;
    sendJson({
      'todo': todo.toJson(),
      'message': 'Todo created successfully',
      'success_url': successUrl,
    }, statusCode: 201);
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
      message = 'An unexpected error occurred while creating the todo';
    }

    sendJson({'error': message, 'success': false}, statusCode: statusCode);
  }

  @override
  Future<void> get() async {
    // Return a form template or instructions for creating a todo
    sendJson({
      'message': 'POST to this endpoint to create a new todo',
      'required_fields': ['title', 'description'],
      'optional_fields': ['completed'],
      'example': {
        'title': 'Learn Dart class views',
        'description': 'Study the framework-agnostic class view pattern',
        'completed': false,
      },
      'validation': {
        'title': 'Required, max 200 characters',
        'description': 'Required, max 1000 characters',
        'completed': 'Optional boolean, defaults to false',
      },
    });
  }
}
