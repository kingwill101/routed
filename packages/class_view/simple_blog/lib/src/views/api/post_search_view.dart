import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../models/post.dart';
import '../../repositories/post_repository.dart';

/// Advanced search view with multiple filters and ordering
///
/// Demonstrates:
/// - Complex query parameter handling
/// - Multiple filter combinations
/// - Dynamic ordering
/// - Faceted search results
/// - Search result highlighting (in response)
class PostSearchView extends ListView<Post> {
  late final PostRepository _repository;

  PostSearchView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  int get paginate => 10;

  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    // Extract search parameters
    final query = await getParam('q');
    final tags = await getParam('tags');
    final author = await getParam('author');
    final status = await getParam('status'); // published, draft, all
    final orderBy = await getParam('order_by') ?? 'created_at';
    final orderDir = await getParam('order_dir') ?? 'desc';

    // Build filters
    final publishedOnly = status != 'all';

    // Use findWithPagination which supports search
    final results = await _repository.findWithPagination(
      page: page,
      pageSize: pageSize,
      search: query,
      publishedOnly: publishedOnly,
    );

    // Sort results
    var items = results.items;

    // Filter by tags if specified
    if (tags != null && tags.isNotEmpty) {
      final tagList = tags.split(',').map((t) => t.trim()).toList();
      items = items.where((post) {
        return post.tags.any((tag) => tagList.contains(tag));
      }).toList();
    }

    // Filter by author if specified
    if (author != null && author.isNotEmpty) {
      items = items.where((post) => post.author.contains(author)).toList();
    }

    items = _sortResults(items, orderBy, orderDir);

    return (items: items, total: results.total);
  }

  List<Post> _sortResults(List<Post> posts, String orderBy, String orderDir) {
    final ascending = orderDir == 'asc';

    switch (orderBy) {
      case 'title':
        posts.sort(
          (a, b) => ascending
              ? a.title.compareTo(b.title)
              : b.title.compareTo(a.title),
        );
        break;
      case 'author':
        posts.sort(
          (a, b) => ascending
              ? a.author.compareTo(b.author)
              : b.author.compareTo(a.author),
        );
        break;
      case 'updated_at':
        posts.sort(
          (a, b) => ascending
              ? a.updatedAt.compareTo(b.updatedAt)
              : b.updatedAt.compareTo(a.updatedAt),
        );
        break;
      case 'created_at':
      default:
        posts.sort(
          (a, b) => ascending
              ? a.createdAt.compareTo(b.createdAt)
              : b.createdAt.compareTo(a.createdAt),
        );
        break;
    }

    return posts;
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final context = await super.getExtraContext();

    // Add search metadata
    context['search_query'] = await getParam('q');
    context['search_tags'] = await getParam('tags');
    context['search_author'] = await getParam('author');
    context['order_by'] = await getParam('order_by') ?? 'created_at';
    context['order_dir'] = await getParam('order_dir') ?? 'desc';

    // Add facets (counts by category)
    final facets = await _getFacets();
    context['facets'] = facets;

    // Add available ordering options
    context['order_options'] = [
      {'value': 'created_at', 'label': 'Date Created'},
      {'value': 'updated_at', 'label': 'Last Updated'},
      {'value': 'title', 'label': 'Title'},
      {'value': 'author', 'label': 'Author'},
    ];

    return context;
  }

  Future<Map<String, int>> _getFacets() async {
    // Get counts for different filters
    final allPosts = await _repository.findAll();
    final publishedCount = allPosts.where((p) => p.isPublished).length;
    final draftCount = allPosts.where((p) => !p.isPublished).length;

    // Get tag counts
    final tagCounts = <String, int>{};
    for (final post in allPosts) {
      for (final tag in post.tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }

    return {
      'total': allPosts.length,
      'published': publishedCount,
      'draft': draftCount,
      ...tagCounts,
    };
  }
}
