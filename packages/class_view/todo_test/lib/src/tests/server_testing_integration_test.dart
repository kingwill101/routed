import 'package:server_testing/server_testing.dart';
import 'package:todo_test/src/repositories/todo_repository.dart';

/// Framework-agnostic server_testing integration tests for Todo app
///
/// This test suite accepts any RequestHandler implementation and proves that our
/// class views work consistently across different frameworks using real HTTP requests.
///
/// Usage:
/// ```dart
/// void main() {
///   group('Shelf Integration', () {
///     runTodoServerTests(() {
///       final repository = TodoRepository();
///       final app = createShelfTodoApp(repository);
///       return (ShelfRequestHandler(app), repository);
///     });
///   });
///
///   group('Routed Integration', () {
///     runTodoServerTests(() {
///       final repository = TodoRepository();
///       final app = createRoutedTodoApp(repository);
///       return (RoutedRequestHandler(app), repository);
///     });
///   });
/// }
/// ```
void runTodoServerTests(
  (RequestHandler handler, TodoRepository repository) Function()
  createHandlerAndRepository,
) {
  test(
    'should demonstrate full CRUD operations with real HTTP requests',
    () async {
      final (handler, repository) = createHandlerAndRepository();

      // Seed test data
      await repository.clear();
      await repository.seed();

      print('🚀 Starting comprehensive server_testing demonstration...');
      print(
        '📊 Repository seeded with ${(await repository.findAll()).total} todos',
      );

      // Create test client with the real handler
      final client = TestClient.inMemory(handler);

      try {
        // ===== LIST VIEW TESTS =====
        print('\n📋 Testing TodoListView...');

        final listResponse = await client.get('/todos');
        listResponse.assertStatus(200).assertJson((json) {
          json
              .has('object_list')
              .has('stats')
              .where('stats.total', 5)
              .where('stats.completed', 1)
              .where('stats.pending', 4)
              .has('page_info')
              .where('page_info.current_page', 1)
              .where('page_info.page_size', 10)
              .has('paginator')
              .where('paginator.count', 5)
              .where('paginator.num_pages', 1);
        });

        print('✅ List view: Status, pagination, and stats assertions passed');

        // Test filtering by completion status
        final completedResponse = await client.get('/todos?completed=true');
        completedResponse.assertStatus(200).assertJson((json) {
          json
              .has('object_list')
              .where('stats.completed', greaterThan(0))
              .where('current_filter', 'true');
        });

        print('✅ List view: Filtering by completion status works');

        // Test search functionality
        final searchResponse = await client.get('/todos?search=Dart');
        searchResponse.assertStatus(200).assertJson((json) {
          json.has('object_list').where('current_search', 'Dart');
        });

        print('✅ List view: Search functionality works');

        // ===== DETAIL VIEW TESTS =====
        print('\n📄 Testing TodoDetailView...');

        final allTodos = await repository.findAll();
        final firstTodo = allTodos.items.first;

        final detailResponse = await client.get('/todos/${firstTodo.id}');
        detailResponse.assertStatus(200).assertJson((json) {
          json
              .has('todo')
              .where('todo.id', firstTodo.id)
              .where('todo.title', firstTodo.title)
              .where('todo.description', firstTodo.description)
              .where('todo.completed', firstTodo.completed);
        });

        print('✅ Detail view: Todo retrieval and serialization works');

        // Test 404 for non-existent todo
        final notFoundResponse = await client.get('/todos/nonexistent');
        notFoundResponse.assertStatus(404).assertJson((json) {
          json.has('error').where('error', contains('not found'));
        });

        print('✅ Detail view: 404 handling works correctly');

        // ===== CREATE VIEW TESTS =====
        print('\n➕ Testing TodoCreateView...');

        // Test GET for form info
        final formInfoResponse = await client.get('/todos/create');
        formInfoResponse.assertStatus(200).assertJson((json) {
          json
              .has('message')
              .has('required_fields')
              .has('example')
              .has('validation')
              .where('message', contains('POST to this endpoint'))
              .count('required_fields', 2);
        });

        print('✅ Create view: Form information endpoint works');

        // Test successful creation
        final createResponse = await client.postJson('/todos/create', {
          'title': 'Server Testing Todo',
          'description': 'Created via server_testing integration',
          'completed': false,
        });

        createResponse.assertStatus(201).assertJson((json) {
          json
              .has('todo')
              .has('message')
              .where('todo.title', 'Server Testing Todo')
              .where(
                'todo.description',
                'Created via server_testing integration',
              )
              .where('todo.completed', false)
              .where('message', contains('created successfully'));
        });

        print('✅ Create view: Todo creation with validation works');

        // Test validation errors
        final validationErrorResponse = await client.postJson('/todos/create', {
          'description': 'Missing title',
        });

        validationErrorResponse.assertStatus(400).assertJson((json) {
          json.has('error').where('error', contains('Title is required'));
        });

        print('✅ Create view: Validation errors handled correctly');

        // Test title length validation
        final longTitleResponse = await client.postJson('/todos/create', {
          'title': 'a' * 201, // 201 characters
          'description': 'This title is too long',
        });

        longTitleResponse.assertStatus(400).assertJson((json) {
          json
              .has('error')
              .where('error', contains('longer than 200 characters'));
        });

        print('✅ Create view: Title length validation works');

        // ===== UPDATE VIEW TESTS =====
        print('\n✏️ Testing TodoUpdateView...');

        // Get a todo to update
        final secondTodo = allTodos.items[1];

        // Test GET for current todo data
        final updateFormResponse = await client.get(
          '/todos/${secondTodo.id}/edit',
        );
        updateFormResponse.assertStatus(200).assertJson((json) {
          json
              .has('todo')
              .has('message')
              .where('todo.id', secondTodo.id)
              .where('message', contains('PUT/PATCH to this endpoint'));
        });

        print('✅ Update view: Form data endpoint works');

        // Test successful update
        final updateResponse = await client.putJson('/todos/${secondTodo.id}', {
          'title': 'Updated via Server Testing',
          'completed': true,
        });

        updateResponse.assertStatus(200).assertJson((json) {
          json
              .has('todo')
              .has('message')
              .where('todo.id', secondTodo.id)
              .where('todo.title', 'Updated via Server Testing')
              .where('todo.completed', true)
              .where('message', contains('updated successfully'));
        });

        print('✅ Update view: Todo updates work correctly');

        // Test partial updates
        final partialUpdateResponse = await client.putJson(
          '/todos/${secondTodo.id}',
          {
            'completed': false, // Only update completion status
          },
        );

        partialUpdateResponse.assertStatus(200).assertJson((json) {
          json
              .has('todo')
              .where('todo.completed', false)
              .where(
                'todo.title',
                'Updated via Server Testing',
              ); // Title unchanged
        });

        print('✅ Update view: Partial updates work correctly');

        // Test update validation
        final updateValidationResponse = await client.putJson(
          '/todos/${secondTodo.id}',
          {
            'title': '', // Empty title
          },
        );

        updateValidationResponse.assertStatus(400).assertJson((json) {
          json.has('error').where('error', contains('cannot be empty'));
        });

        print('✅ Update view: Update validation works');

        // ===== DELETE VIEW TESTS =====
        print('\n🗑️ Testing TodoDeleteView...');

        // Get the created todo for deletion
        final todosBeforeDelete = await repository.findAll();
        final todoToDelete = todosBeforeDelete.items.firstWhere(
          (t) => t.title == 'Updated via Server Testing',
        );
        final initialCount = todosBeforeDelete.total;

        // Test GET for delete confirmation
        final deleteFormResponse = await client.get(
          '/todos/${todoToDelete.id}/delete',
        );
        deleteFormResponse.assertStatus(200).assertJson((json) {
          json
              .has('todo')
              .has('message')
              .where('todo.id', todoToDelete.id)
              .where('message', contains('DELETE to this endpoint'))
              .where('warning', 'This action cannot be undone');
        });

        print('✅ Delete view: Delete confirmation endpoint works');

        // Test successful deletion
        final deleteResponse = await client.delete('/todos/${todoToDelete.id}');
        deleteResponse.assertStatus(200).assertJson((json) {
          json
              .has('message')
              .has('deleted_todo')
              .where('deleted_todo.id', todoToDelete.id)
              .where('message', contains('deleted successfully'));
        });

        // Verify todo was actually deleted from repository
        final todosAfterDelete = await repository.findAll();
        expect(todosAfterDelete.total, equals(initialCount - 1));

        final deletedTodo = await repository.findById(todoToDelete.id);
        expect(deletedTodo, isNull);

        print('✅ Delete view: Todo deletion works correctly');
        print('✅ Delete view: Repository state correctly updated');

        // ===== COMPREHENSIVE INTEGRATION VERIFICATION =====
        print('\n🔍 Final integration verification...');

        // Verify the list reflects all our changes
        final finalListResponse = await client.get('/todos');
        finalListResponse.assertStatus(200).assertJson((json) {
          json
              .has('stats')
              .where('stats.total', initialCount - 1); // One todo deleted
        });

        print('✅ Integration: All operations properly reflected in list view');

        print('\n🎉 ALL SERVER_TESTING INTEGRATION TESTS PASSED!');
        print('✨ Framework successfully demonstrated with:');
        print('   • Clean CreateView<Todo> syntax (no context generics)');
        print('   • Real HTTP requests (no mocking)');
        print('   • Framework-agnostic adapter pattern');
        print('   • Django-inspired class views');
        print('   • Powerful server_testing assertions');
        print('   • Full CRUD operations with validation');
        print('   • JSON response testing with AssertableJson');
        print('   • Repository integration');
      } catch (e, stackTrace) {
        print('❌ Test failed: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      } finally {
        await client.close();
      }
    },
  );
}
