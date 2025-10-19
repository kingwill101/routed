import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../models/post.dart';
import '../../repositories/post_repository.dart';

/// Search form for filtering posts
class PostSearchForm extends Form {
  PostSearchForm({Map<String, dynamic>? data, super.isBound = false})
    : super(
        data: data ?? {},
        files: {},
        fields: {
          'search': CharField<String>(required: false, maxLength: 200),
          'page_size': CharField<String>(
            required: false,
          ), // Using CharField instead of ChoiceField
        },
      );
}

/// Web view for listing blog posts with search form
/// Uses template-first approach with automatic HTML rendering
class WebPostListView extends BaseFormView {
  late final PostRepository _repository;

  WebPostListView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  String get templateName => 'posts/list';

  int get paginate => 5; // Default 5 posts per page

  @override
  Form getForm([Map<String, dynamic>? data]) {
    if (data != null) {
      return PostSearchForm(data: data, isBound: true);
    }

    // Default form values
    final currentData = <String, dynamic>{'page_size': '5'};

    return PostSearchForm(data: currentData, isBound: false);
  }

  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    final search = await getParam('search');

    return await _repository.findWithPagination(
      page: page,
      pageSize: pageSize,
      publishedOnly: true,
      search: search,
    );
  }

  Future<({List<Post> objects, int total, int pages})>
  getPaginatedResults() async {
    // Get page_size from query parameter, fallback to paginate property
    final pageSizeParam = await getParam('page_size');
    final pageSize = (pageSizeParam != null)
        ? (int.tryParse(pageSizeParam) ?? paginate)
        : paginate;

    // Get page from query parameter
    final pageParam = await getParam('page');
    final page = int.tryParse(pageParam ?? '1') ?? 1;

    final result = await getObjectList(page: page, pageSize: pageSize);
    final total = result.total;
    final pages = (total / pageSize).ceil();

    return (objects: result.items, total: total, pages: pages);
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final results = await getPaginatedResults();
    final searchQuery = await getParam('search') ?? '';

    // Get actual pagination values used
    final pageSizeParam = await getParam('page_size');
    final actualPageSize = (pageSizeParam != null)
        ? (int.tryParse(pageSizeParam) ?? paginate)
        : paginate;
    final pageParam = await getParam('page');
    final currentPage = int.tryParse(pageParam ?? '1') ?? 1;

    // Calculate pagination range (show up to 5 page links)
    final totalPages = results.pages;
    int startPage = 1;
    int endPage = totalPages;

    if (totalPages > 5) {
      // Show 5 page links centered around current page
      startPage = (currentPage - 2).clamp(1, totalPages - 4);
      endPage = (startPage + 4).clamp(5, totalPages);

      // Adjust start if we're near the end
      if (endPage == totalPages) {
        startPage = (totalPages - 4).clamp(1, totalPages);
      }
    }

    return {
      'object_list': results.objects.map((p) => p.toJson()).toList(),
      'paginator': {
        'count': results.total,
        'num_pages': results.pages,
        'page_size': actualPageSize,
        'current_page': currentPage,
        'has_next': currentPage < results.pages,
        'has_previous': currentPage > 1,
        'start_page': startPage,
        'end_page': endPage,
      },
      'start_page': startPage,
      'end_page': endPage,
      'search_query': searchQuery,
      'show_search': true,
      'page_title': searchQuery.isNotEmpty
          ? 'Search Results for "$searchQuery"'
          : 'Latest Blog Posts',
      'page_description': searchQuery.isNotEmpty
          ? 'Found posts matching your search criteria.'
          : 'Discover articles about web development, tutorials, and more.',
    };
  }
}
