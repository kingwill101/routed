import 'package:routed/routed.dart' as routed;
import 'package:routed_class_view/routed_class_view.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';
import 'package:todo_test/todo_test.dart';

/// Create the Todo app with Routed and class view extensions
routed.Engine _createRoutedTodoApp(TodoRepository repository) {
  final app = routed.Engine();

  // ✨ Clean route registration using routed class_view extensions!

  // List todos (with pagination, filtering, search)
  app.getView('/todos', () => TodoListView(repository));

  // Create todo (handles both GET for form info and POST for creation)
  // Note: Routed uses different route syntax than Shelf
  app.post(
    '/todos/create',
    RoutedViewHandler.handle(() => TodoCreateView(repository)),
  );
  app.get(
    '/todos/create',
    RoutedViewHandler.handle(() => TodoCreateView(repository)),
  );

  // Detail view for single todo
  app.get(
    '/todos/{id}',
    RoutedViewHandler.handle(() => TodoDetailView(repository)),
  );

  // Update todo (handles GET for form info, PUT for updates)
  app.get(
    '/todos/{id}/edit',
    RoutedViewHandler.handle(() => TodoUpdateView(repository)),
  );
  app.putView('/todos/{id}', () => TodoUpdateView(repository));

  // Delete todo (handles GET for confirmation, DELETE for deletion)
  app.get(
    '/todos/{id}/delete',
    RoutedViewHandler.handle(() => TodoDeleteView(repository)),
  );
  app.deleteView('/todos/{id}', () => TodoDeleteView(repository));

  return app;
}

void main() {
  group('Routed Class View - Todo App Server Testing Integration', () {
    runTodoServerTests(() {
      // Create repository and app for each test
      final repository = TodoRepository();
      final app = _createRoutedTodoApp(repository);
      final handler = RoutedRequestHandler(app);

      return (handler, repository);
    });
  });
}
