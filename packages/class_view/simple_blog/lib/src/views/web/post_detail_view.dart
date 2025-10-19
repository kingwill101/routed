import 'package:class_view/class_view.dart';
import 'package:simple_blog/src/forms/comment.dart';

import '../../database/database.dart';
import '../../models/post.dart';
import '../../repositories/post_repository.dart';

/// Web post detail view with comment form
/// Uses template-first approach with automatic HTML rendering
class WebPostDetailView extends BaseFormView {
  late final PostRepository _repository;

  WebPostDetailView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  String get templateName => 'posts/detail';

  @override
  Form getForm([Map<String, dynamic>? data]) {
    return CommentForm(data: data, isBound: data != null);
  }

  @override
  Future<void> formValid(Form form) async {
    final comment = form as CommentForm;
    final post = await getPost();

    if (post == null) {
      throw HttpException.notFound('Post not found');
    }

    // Here you would save the comment to your database
    print('Comment submitted for post "${post.title}":');
    print('Name: ${comment.cleanedData['name']}');
    print('Email: ${comment.cleanedData['email']}');
    print('Comment: ${comment.cleanedData['comment']}');

    // Redirect to same page with success message
    redirect('/posts/${post.slug}?success=comment');
  }

  Future<Post?> getPost() async {
    final slug = await getParam('slug');
    if (slug == null) return null;

    return await _repository.findBySlug(slug);
  }

  /// Get related posts based on tags
  Future<List<Map<String, dynamic>>> _getRelatedPosts(Post currentPost) async {
    if (currentPost.tags.isEmpty) return [];

    // Find posts with similar tags
    final allPosts = await _repository.findAll(publishedOnly: true);
    final relatedPosts = allPosts
        .where(
          (p) =>
              p.id != currentPost.id &&
              p.tags.any((tag) => currentPost.tags.contains(tag)),
        )
        .take(2)
        .map((p) => p.toJson())
        .toList();

    return relatedPosts;
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final post = await getPost();
    if (post == null) {
      throw HttpException.notFound('Post not found');
    }

    // Check for success message
    final success = await getParam('success');

    return {
      'post': post.toJson(),
      'page_title': post.title,
      'page_description': _extractExcerpt(post.content),
      'meta_tags': post.tags,
      'author': post.author,
      'published_date': post.createdAt.toIso8601String(),
      'updated_date': post.updatedAt.toIso8601String(),
      'related_posts': await _getRelatedPosts(post),
      'success_message': success == 'comment'
          ? 'Thank you for your comment!'
          : null,
    };
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
