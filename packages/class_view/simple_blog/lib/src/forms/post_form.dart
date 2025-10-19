import 'package:class_view/class_view.dart';
import 'package:uuid/uuid.dart';

import '../models/post.dart';

/// Form for creating and editing blog posts
class PostForm extends Form {
  PostForm({
    Map<String, dynamic>? data,
    Map<String, dynamic>? files,
    super.renderer,
    Post? instance,
  }) : super(
         isBound: data != null,
         data: data ?? {},
         files: files ?? {},
         initial: instance?.toJson() ?? {},
         fields: {
           'title': CharField(
             label: 'Title',
             maxLength: 200,
             required: true,
             helpText: 'Maximum 200 characters',
             widget: TextInput(
               attrs: {
                 'placeholder': 'Enter your post title...',
                 'class':
                     'w-full px-4 py-3 text-lg border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400',
               },
             ),
           ),
           'author': CharField(
             label: 'Author',
             required: true,
             widget: TextInput(
               attrs: {
                 'placeholder': 'Your name...',
                 'class':
                     'w-full px-4 py-3 border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400',
               },
             ),
           ),
           'slug': CharField(
             label: 'URL Slug',
             required: false,
             helpText: 'Leave empty to auto-generate from title',
             widget: TextInput(
               attrs: {
                 'placeholder': 'auto-generated-from-title',
                 'class':
                     'w-full px-4 py-3 border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400 text-gray-600',
               },
             ),
           ),
           'content': CharField(
             label: 'Content',
             required: true,
             helpText:
                 'Supports Markdown formatting: **bold**, *italic*, # headers, etc.',
             widget: Textarea(
               attrs: {
                 'rows': '12',
                 'placeholder':
                     'Write your post content here... You can use Markdown formatting.',
                 'class':
                     'w-full px-4 py-3 border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400 resize-y min-h-[200px]',
               },
             ),
           ),
           'tags': CharField(
             label: 'Tags',
             required: false,
             helpText: 'Separate multiple tags with commas',
             widget: TextInput(
               attrs: {
                 'placeholder': 'web-development, tutorial, dart',
                 'class':
                     'w-full px-4 py-3 border border-gray-200 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 placeholder-gray-400',
               },
             ),
           ),
           'isPublished': BooleanField(
             label: 'Publish immediately',
             required: false,
             helpText: 'Uncheck to save as draft',
             widget: CheckboxInput(
               attrs: {
                 'class':
                     'w-5 h-5 text-blue-600 bg-white border-2 border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:ring-offset-0 transition-all duration-200',
               },
             ),
           ),
         },
       );

  /// Generate slug from title if not provided
  String _generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  void clean() {
    super.clean();

    // Auto-generate slug if not provided
    final title = cleanedData['title'] as String?;
    final slug = cleanedData['slug'] as String?;

    if (title != null && (slug == null || slug.trim().isEmpty)) {
      cleanedData['slug'] = _generateSlug(title);
    }

    // Parse tags from comma-separated string to list
    final tagsString = cleanedData['tags'] as String?;
    if (tagsString != null && tagsString.trim().isNotEmpty) {
      final tagsList = tagsString
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
      cleanedData['tags'] = tagsList;
    } else {
      cleanedData['tags'] = <String>[];
    }
  }

  /// Convert cleaned data to Post object
  Post toPost({String? id}) {
    // Use existing id or generate new one
    final postId = id ?? const Uuid().v4();

    return Post(
      id: postId,
      title: cleanedData['title'] as String,
      author: cleanedData['author'] as String,
      slug: cleanedData['slug'] as String,
      content: cleanedData['content'] as String,
      tags: cleanedData['tags'] as List<String>,
      isPublished: cleanedData['isPublished'] as bool? ?? false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Check if the form is valid by running validation
  Future<bool> checkIsValid() async {
    await fullClean();
    return errors.isEmpty;
  }
}
