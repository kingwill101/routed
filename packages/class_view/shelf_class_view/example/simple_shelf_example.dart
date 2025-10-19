import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';

// Example model
class Post {
  final String id;
  final String title;
  final String content;

  Post(this.id, this.title, this.content);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
  };
}

// Mock repository
class PostRepository {
  static final List<Post> _posts = [
    Post('1', 'First Post', 'This is the first post'),
    Post('2', 'Second Post', 'This is the second post'),
    Post('3', 'Third Post', 'This is the third post'),
  ];

  static Future<({List<Post> items, int total})> findAll({
    int page = 1,
    int pageSize = 10,
  }) async {
    return (items: _posts, total: _posts.length);
  }

  static Future<Post?> findById(String? id) async {
    try {
      return _posts.firstWhere((post) => post.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<Post> create(Map<String, dynamic> data) async {
    final post = Post(
      (int.parse(_posts.last.id) + 1).toString(),
      data['title'] as String,
      data['content'] as String,
    );
    _posts.add(post);
    return post;
  }
}

// Views using the new architecture
class PostListView extends ListView<Post> {
  @override
  Future<({List<Post> items, int total})> getObjectList({
    int page = 1,
    int pageSize = 10,
  }) async {
    return await PostRepository.findAll(page: page, pageSize: pageSize);
  }

  @override
  Future<void> get() async {
    final result = await getObjectList();
    sendJson({
      'posts': result.items.map((p) => p.toJson()).toList(),
      'total': result.total,
    });
  }
}

class PostDetailView extends DetailView<Post> {
  @override
  Future<Post?> getObject() async {
    final id = await getParam('id');
    return await PostRepository.findById(id);
  }

  @override
  Future<void> get() async {
    final post = await getObjectOr404();
    sendJson(post.toJson());
  }
}

class PostCreateView extends CreateView<Post> {
  @override
  Future<Post> performCreate(Map<String, dynamic> data) async {
    return await PostRepository.create(data);
  }

  Future<Post> createObject(Map<String, dynamic> data) async {
    return await PostRepository.create(data);
  }

  @override
  String get successUrl => '/posts';

  @override
  Future<void> get() async {
    sendJson({'message': 'Send POST to create a post'});
  }
}

void main() async {
  final router = Router();

  // Using the convenient extension methods
  router.getView('/posts', () => PostListView());
  router.getView('/posts/<id>', () => PostDetailView());
  router.allView('/posts/create', () => PostCreateView());

  // Start the server
  final server = await io.serve(router.call, InternetAddress.anyIPv4, 8080);
  print('Server running on http://${server.address.host}:${server.port}');
  print('Try:');
  print('  GET  http://localhost:8080/posts');
  print('  GET  http://localhost:8080/posts/1');
  print('  GET  http://localhost:8080/posts/create');
  print('  POST http://localhost:8080/posts/create (with JSON body)');
}
