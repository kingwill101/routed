import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

/// Detail view for individual blog posts
class PostDetailView extends DetailView<Post> {
  late final PostRepository _repository;

  PostDetailView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  Future<Post?> getObject() async {
    final slug = await getParam('slug');
    if (slug == null) return null;

    return await _repository.findBySlug(slug);
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final post = await getObject();
    if (post == null) return {};

    return {
      'page_title': post.title,
      'page_description': _extractExcerpt(post.content),
      'meta_tags': post.tags,
      'author': post.author,
      'published_date': post.createdAt.toIso8601String(),
      'updated_date': post.updatedAt.toIso8601String(),
    };
  }

  Future<void> onObjectNotFound() async {
    sendJson({
      'error': 'Post not found',
      'message': 'The requested blog post could not be found.',
    }, statusCode: 404);
  }

  /// Extract excerpt from content for meta description
  String _extractExcerpt(String content, {int maxLength = 160}) {
    // Remove markdown formatting
    final cleaned = content
        .replaceAll(RegExp(r'#+ '), '')
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();

    if (cleaned.length <= maxLength) return cleaned;

    // Find the last complete word within the limit
    final truncated = cleaned.substring(0, maxLength);
    final lastSpace = truncated.lastIndexOf(' ');

    return lastSpace > 0
        ? '${truncated.substring(0, lastSpace)}...'
        : '$truncated...';
  }
}
