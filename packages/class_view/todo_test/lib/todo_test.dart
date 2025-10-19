/// Support for sharing todo test cases across different framework adapters.
///
/// This package provides shared test cases that can be run against any
/// ViewAdapter implementation to ensure consistent behavior across frameworks.
library;

// Export models and repositories for testing
export 'src/models/todo.dart';
export 'src/repositories/todo_repository.dart';

// Export shared test cases (server_testing only)
export 'src/tests/server_testing_integration_test.dart';
export 'src/todo_test_base.dart';
export 'src/views/todo_create_view.dart';
export 'src/views/todo_delete_view.dart';
export 'src/views/todo_detail_view.dart';

// Export views for testing
export 'src/views/todo_list_view.dart';
export 'src/views/todo_update_view.dart';

// TODO: Export any libraries intended for clients of this package.
