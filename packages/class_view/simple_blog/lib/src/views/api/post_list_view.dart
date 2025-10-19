import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

/// List view for blog posts with pagination and search
class PostListView extends ListView<Post> {
  late final PostRepository _repository;

  PostListView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  int get paginate => 5; // Default 5 posts per page

  @override
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

  @override
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
  Future<Map<String, dynamic>> getContextData() async {
    final baseContext = await super.getContextData();
    final results = await getPaginatedResults();
    final searchQuery = await getParam('search') ?? '';

    // Get actual pagination values used
    final pageSizeParam = await getParam('page_size');
    final actualPageSize = (pageSizeParam != null)
        ? (int.tryParse(pageSizeParam) ?? paginate)
        : paginate;
    final pageParam = await getParam('page');
    final currentPage = int.tryParse(pageParam ?? '1') ?? 1;

    return {
      ...baseContext,
      'object_list': results.objects,
      'paginator': {
        'count': results.total,
        'num_pages': results.pages,
        'page_size': actualPageSize,
        'current_page': currentPage,
        'has_next': currentPage < results.pages,
        'has_previous': currentPage > 1,
      },
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
