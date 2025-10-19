import 'package:class_view/class_view.dart';
import 'package:simple_blog/simple_blog.dart';

/// Home page view with dashboard information
class HomeView extends View with ContextMixin {
  late final PostRepository _repository;

  HomeView() {
    _repository = PostRepository(DatabaseService.instance);
  }

  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<Map<String, dynamic>> getExtraContext() async {
    final recentPosts = await _repository.findAll(publishedOnly: true);
    final totalPosts = await _repository.findAll();

    return {
      'page_title': 'SimpleBlog - Showcasing Class View Features',
      'page_description':
          'A demonstration blog built with Dart class_view framework',
      'recent_posts': recentPosts.take(3).map((p) => p.toJson()).toList(),
      'total_posts': totalPosts.length,
      'published_posts': recentPosts.length,
      'features': [
        {
          'title': 'Full CRUD Operations',
          'description':
              'Complete Create, Read, Update, Delete functionality using class_view',
          'icon': '✅',
        },
        {
          'title': 'Django-style Views',
          'description':
              'Clean, composable views with mixins for maximum flexibility',
          'icon': '🏗️',
        },
        {
          'title': 'Search & Pagination',
          'description':
              'Built-in search functionality with efficient pagination',
          'icon': '🔍',
        },
        {
          'title': 'Form Validation',
          'description':
              'Robust form handling with validation and error management',
          'icon': '📝',
        },
        {
          'title': 'RESTful API',
          'description':
              'JSON API endpoints that work seamlessly with the views',
          'icon': '🌐',
        },
        {
          'title': 'Template System',
          'description':
              'Powerful Liquid templating with inheritance and components',
          'icon': '🎨',
        },
      ],
    };
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    sendJson(contextData);
  }
}
