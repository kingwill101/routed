import 'package:class_view/class_view.dart';

import '../../database/database.dart';
import '../../forms/post_form.dart';
import '../../forms/update_post.dart' show UpdatePostForm;
import '../../models/post.dart';
import '../../repositories/post_repository.dart';

/// Base web form view for posts using proper Form classes
abstract class WebPostFormView extends BaseFormView {
  late final PostRepository _repository;

  WebPostFormView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  List<String> get allowedMethods => ['GET', 'POST'];

  @override
  String get templateName => 'forms/post_form';

  /// Get the form instance for this view
  @override
  PostForm getForm([Map<String, dynamic>? data]);

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    return {
      'page_title': await getPageTitle(),
      'page_description': await getPageDescription(),
    };
  }

  Future<String> getPageTitle();

  Future<String> getPageDescription();

  /// Handle valid form submission - implemented by subclasses
  @override
  Future<void> formValid(Form form);
}

/// Web view for creating new posts
class WebPostCreateView extends WebPostFormView {
  @override
  PostForm getForm([Map<String, dynamic>? data]) {
    return PostForm(data: data, renderer: null);
  }

  @override
  Future<String> getPageTitle() async => 'Create New Post';

  @override
  Future<String> getPageDescription() async =>
      'Share your thoughts with the world. Create a new blog post below.';

  @override
  Future<void> formValid(Form form) async {
    try {
      final createForm = form as PostForm;
      final post = createForm.toPost();
      await _repository.create(post);

      // Redirect to the new post detail page
      redirect('/posts/${post.slug}');
    } catch (e) {
      throw Exception('Failed to create post: $e');
    }
  }
}

/// Web view for editing existing posts using ModelFormView pattern
class WebPostEditView extends ModelFormView<Post> {
  late final PostRepository _repository;

  WebPostEditView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  String get templateName => 'forms/post_form.liquid';

  @override
  String? get successUrl => null; // Will redirect to post detail

  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    if (id == null) {
      throw Exception('Post ID not provided');
    }

    final post = await _repository.findById(id);
    if (post == null) {
      throw Exception('Post not found');
    }

    return post;
  }

  @override
  Form createForm(Post? instance, [Map<String, dynamic>? data]) {
    if (instance == null) {
      throw Exception('Post instance required for editing');
    }
    return PostForm(
      instance: instance,
      data: {...data ?? {}, ...instance.toJson()},
      renderer: null,
    );
  }

  @override
  Future<Post> saveForm(Form form) async {
    final updateForm = form as UpdatePostForm;
    final updatedPost = await updateForm.updatePost();
    await _repository.update(updatedPost);
    return updatedPost;
  }

  @override
  Future<void> onSaveSuccess(Post object) async {
    // Redirect to the updated post detail page instead of using successUrl
    redirect('/posts/${object.slug}');
  }

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final post = await getObject();
    if (post == null) {
      throw Exception('Post not found');
    }
    return {
      'post': post.toJson(),
      'page_title': 'Edit Post: ${post.title}',
      'page_description':
          'Update your blog post and share your latest thoughts.',
    };
  }
}
