import 'dart:convert';

import 'package:routed/routed.dart';

/// Simple in-memory representation of a blog post.
class Post {
  Post({required this.id, required this.title, required this.content});

  final String id;
  final String title;
  final String content;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
  };
}

/// Minimal repository used by the example.
class BlogRepository {
  BlogRepository()
    : _posts = {
        '1': Post(
          id: '1',
          title: 'Welcome to Routed',
          content: 'Routed lets you compose HTTP apps with ease.',
        ),
        '2': Post(
          id: '2',
          title: 'Declarative Middleware',
          content: 'Combine middleware stacks per route, group, or engine.',
        ),
      };

  final Map<String, Post> _posts;

  List<Post> all() => _posts.values.toList(growable: false);

  Post? find(String id) => _posts[id];

  Post create({required String title, required String content}) {
    final id = (_posts.length + 1).toString();
    final post = Post(id: id, title: title, content: content);
    _posts[id] = post;
    return post;
  }

  bool remove(String id) => _posts.remove(id) != null;
}

/// Builds the blog engine so tests can reuse it without starting an HTTP port.
Engine createBlogApp({BlogRepository? repository}) {
  final repo = repository ?? BlogRepository();
  final router = Router();

  router.get('/posts', (ctx) {
    final posts = repo.all().map((post) => post.toJson()).toList();
    return ctx.json({'posts': posts});
  });

  router.get('/posts/{id}', (ctx) {
    final id = ctx.param('id');
    final post = id != null ? repo.find(id) : null;
    if (post == null) {
      return ctx.json({
        'error': 'Post not found',
      }, statusCode: HttpStatus.notFound);
    }
    return ctx.json(post.toJson());
  });

  router.post('/posts', (ctx) async {
    final payload =
        jsonDecode(await ctx.request.body()) as Map<String, dynamic>;
    final title = payload['title']?.toString();
    final content = payload['content']?.toString();
    if (title == null || title.isEmpty || content == null || content.isEmpty) {
      return ctx.json({
        'error': 'Both "title" and "content" are required.',
      }, statusCode: HttpStatus.badRequest);
    }
    final created = repo.create(title: title, content: content);
    return ctx.json(created.toJson(), statusCode: HttpStatus.created);
  });

  router.delete('/posts/{id}', (ctx) {
    final id = ctx.param('id');
    if (id == null || !repo.remove(id)) {
      return ctx.json({
        'error': 'Post not found',
      }, statusCode: HttpStatus.notFound);
    }
    return ctx.json({'status': 'deleted'});
  });

  final engine = Engine()..use(router, prefix: '/api');
  return engine;
}

Future<void> main(List<String> args) async {
  final engine = createBlogApp();
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 3000 : 3000;
  print('Blog example listening on http://localhost:$port/api/posts');
  await engine.serve(port: port);
}
