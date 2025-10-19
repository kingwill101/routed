import 'package:simple_blog/simple_blog.dart' show Post;

import 'post_form.dart';

/// Form specifically for updating existing posts
class UpdatePostForm extends PostForm {
  final Post instance;

  UpdatePostForm({
    required this.instance,
    super.data,
    super.files,
    super.renderer,
  }) : super(instance: instance);

  /// Update the existing post with form data
  Future<Post> updatePost() async {
    final isValid = await checkIsValid();
    if (!isValid) {
      throw StateError('Form is not valid');
    }

    return Post(
      id: instance.id,
      title: cleanedData['title'] as String,
      author: cleanedData['author'] as String,
      slug: cleanedData['slug'] as String,
      content: cleanedData['content'] as String,
      tags: cleanedData['tags'] as List<String>,
      isPublished: cleanedData['isPublished'] as bool? ?? false,
      createdAt: instance.createdAt,
      // Keep original creation date
      updatedAt: DateTime.now(),
    );
  }
}
