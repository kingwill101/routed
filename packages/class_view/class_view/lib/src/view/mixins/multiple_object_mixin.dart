import 'dart:async';

import 'context_mixin.dart';

/// Mixin that provides functionality for working with lists of objects
mixin MultipleObjectMixin<T> on ContextMixin {
  /// Whether to allow empty results
  bool get allowEmpty => true;

  /// Number of items per page when using pagination
  int? get paginate => null;

  /// Name of the query parameter for page number
  String get pageParam => 'page';

  /// Ordering for the objects
  List<String> get ordering => const [];

  /// Name of the context variable to use for the object list
  String? get contextObjectName => null;

  /// Get the list of objects
  Future<({List<T> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    throw UnimplementedError('Subclasses must implement getObjectList');
  }

  /// Get paginated results
  Future<({List<T> objects, int total, int pages})>
  getPaginatedResults() async {
    final pageSize = paginate;
    if (pageSize == null) {
      final result = await getObjectList();
      return (objects: result.items, total: result.total, pages: 1);
    }

    // Implement pagination
    final String? param = await getParam(pageParam);
    final page = int.tryParse(param ?? '1') ?? 1;
    final result = await getObjectList(page: page, pageSize: pageSize);
    final total = result.total;
    final pages = (total / pageSize).ceil();

    return (objects: result.items, total: total, pages: pages);
  }

  /// Get the context variable name for the object list
  String getContextObjectName() {
    if (contextObjectName != null) {
      return contextObjectName!;
    }
    return 'object_list';
  }

  /// Add the object list to the context data
  @override
  Future<Map<String, dynamic>> getContextData() async {
    final baseContext = await super.getContextData();
    final results = await getPaginatedResults();
    final data = {...baseContext, getContextObjectName(): results.objects};

    if (paginate != null) {
      data['paginator'] = {
        'count': results.total,
        'num_pages': results.pages,
        'page_size': paginate,
      };
    }

    return data;
  }
}
