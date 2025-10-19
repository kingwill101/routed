import 'package:class_view/class_view.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';

/// List view for todos with pagination and filtering
///
/// Demonstrates clean ListView implementation following Django-like patterns.
/// Supports pagination, completion status filtering, and search.
class TodoListView extends ListView<Todo> {
  final TodoRepository _repository;

  TodoListView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  int get paginate => 10;

  @override
  Future<({List<Todo> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final search = await getParam('search');
    final currentPage = int.tryParse(await getParam('page') ?? '1') ?? 1;

    if (search != null && search.isNotEmpty) {
      final results = await _repository.search(search);
      return (items: results, total: results.length);
    }

    return await _repository.findAll(page: currentPage, pageSize: pageSize);
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final stats = await _repository.getStats();
    final currentParams = await getParams();

    return {
      'stats': stats,
      'current_filter': currentParams['completed'],
      'current_search': currentParams['search'],
      'page_info': {
        'current_page': int.tryParse(await getParam('page') ?? '1') ?? 1,
        'page_size': paginate,
      },
    };
  }
}

/// Stats view that returns todo statistics
class TodoStatsView extends View with ContextMixin {
  final TodoRepository _repository;

  TodoStatsView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  Future<void> get() async {
    final stats = await _repository.getStats();
    sendJson({
      'stats': stats,
      'message': 'Todo statistics retrieved successfully',
    });
  }
}

/// Search view for todos
class TodoSearchView extends View with ContextMixin {
  final TodoRepository _repository;

  TodoSearchView([TodoRepository? repository])
    : _repository = repository ?? TodoRepository();

  @override
  Future<void> get() async {
    final query = await getParam('q') ?? '';

    if (query.isEmpty) {
      sendJson({
        'results': <Todo>[],
        'message': 'Please provide a search query using ?q=search_term',
      });
      return;
    }

    final results = await _repository.search(query);
    sendJson({
      'results': results.map((todo) => todo.toJson()).toList(),
      'count': results.length,
      'query': query,
      'message': 'Search completed successfully',
    });
  }
}
