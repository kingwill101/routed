// import 'dart:async';
//
// import 'package:routed/routed.dart';
//
// // Models
// class Post {
//   final String id;
//   final String title;
//   final String content;
//   final DateTime createdAt;
//
//   Post({
//     required this.id,
//     required this.title,
//     required this.content,
//     DateTime? createdAt,
//   }) : createdAt = createdAt ?? DateTime.now();
// }
//
// class Comment {
//   final String id;
//   final String postId;
//   final String author;
//   final String content;
//   final DateTime createdAt;
//
//   Comment({
//     required this.id,
//     required this.postId,
//     required this.author,
//     required this.content,
//     DateTime? createdAt,
//   }) : createdAt = createdAt ?? DateTime.now();
// }
//
// // Repositories
// class PostRepository {
//   final List<Post> _posts = [
//     Post(
//       id: '1',
//       title: 'Getting Started with Routed',
//       content: 'Routed is a fast, flexible HTTP router for Dart...',
//     ),
//     Post(
//       id: '2',
//       title: 'Class-Based Views in Routed',
//       content:
//           'Class-based views provide a structured way to organize your code...',
//     ),
//   ];
//
//   Future<List<Post>> getAll() async => _posts;
//
//   Future<Post?> getById(String id) async {
//     try {
//       return _posts.firstWhere((p) => p.id == id);
//     } catch (_) {
//       return null;
//     }
//   }
//
//   Future<void> add(Post post) async {
//     _posts.add(post);
//   }
//
//   Future<bool> update(Post post) async {
//     final index = _posts.indexWhere((p) => p.id == post.id);
//     if (index == -1) return false;
//
//     _posts[index] = post;
//     return true;
//   }
//
//   Future<bool> delete(String id) async {
//     final initialLength = _posts.length;
//     _posts.removeWhere((p) => p.id == id);
//     return _posts.length < initialLength;
//   }
// }
//
// class CommentRepository {
//   final List<Comment> _comments = [
//     Comment(
//       id: '1',
//       postId: '1',
//       author: 'Alice',
//       content: 'Great article!',
//     ),
//     Comment(
//       id: '2',
//       postId: '1',
//       author: 'Bob',
//       content: 'Very helpful, thanks!',
//     ),
//   ];
//
//   Future<List<Comment>> getByPostId(String postId) async {
//     return _comments.where((c) => c.postId == postId).toList();
//   }
//
//   Future<void> add(Comment comment) async {
//     _comments.add(comment);
//   }
// }
//
// // Authentication middleware
// FutureOr<void> authMiddleware(EngineContext context) async {
//   final authHeader = context.request.headers.value('Authorization');
//   if (authHeader == null || !authHeader.startsWith('Bearer ')) {
//     context.response.statusCode = 401;
//     context.json({'error': 'Unauthorized'});
//     context.abort();
//   }
//
// // In a real app, you would validate the token
// // For this example, we'll just check if it's not empty
//   final token = authHeader?.substring(7);
//   if (token == null || token.isEmpty) {
//     context.response.statusCode = 401;
//     context.json({'error': 'Invalid token'});
//     context.abort();
//   }
//
//   context.setContextData('user', {'id': '123', 'name': 'Admin'});
//
//   await context.next();
// }
//
// // Views
// class PostListView extends ListView<Post> {
//   final PostRepository repository;
//
//   PostListView(this.repository);
//
//   @override
//   Future<({List<Post> items, int total})> Function(String p1,
//           {int? page, int? pageSize})?
//       get query => (String pageParam, {int? page, int? pageSize}) async {
//             final items = await repository.getAll();
//             return (items: items, total: items.length);
//           };
//
//   @override
//   Future<Map<String, dynamic>> getContextData(EngineContext context) async {
//     final baseContext = await super.getContextData(context);
//     final posts = await getObjectList(context);
//     return {
//       ...baseContext,
//       'posts': posts.items
//           .map((post) => {
//                 'id': post.id,
//                 'title': post.title,
//                 'createdAt': post.createdAt,
//               })
//           .toList(),
//     };
//   }
//
//   @override
//   String? get templateName => 'post_list.html';
// }
//
// class PostDetailView extends DetailView<Post> {
//   final PostRepository postRepository;
//   final CommentRepository commentRepository;
//
//   PostDetailView(this.postRepository, this.commentRepository);
//
//   @override
//   Future<Post?> getObject(EngineContext context) async {
//     final id = context.param('id');
//     if (id == null) return null;
//     return await postRepository.getById(id);
//   }
//
//   @override
//   Future<Map<String, dynamic>> getContextData(EngineContext context) async {
//     final object = await getObject(context);
//     if (object == null) return {};
//
//     final comments = await commentRepository.getByPostId(object.id);
//
//     return {
//       'object': object,
//       'post': {
//         'id': object.id,
//         'title': object.title,
//         'content': object.content,
//         'createdAt': object.createdAt.toIso8601String(),
//       },
//       'comments': comments
//           .map((comment) => {
//                 'id': comment.id,
//                 'author': comment.author,
//                 'content': comment.content,
//                 'createdAt': comment.createdAt.toIso8601String(),
//               })
//           .toList(),
//     };
//   }
//
//   @override
//   String? get templateName => 'post_detail.html';
// }
//
// class PostCreateView extends View {
//   final PostRepository repository;
//
//   PostCreateView(this.repository);
//
//   @override
//   List<String> get allowedMethods => ['POST'];
//
//   @override
//   Future<void> post(EngineContext context) async {
//     try {
//       // Use the built-in data binding methods
//       final data = <String, dynamic>{};
//
//       // Validate required fields
//       await context.validate({
//         'title': 'required',
//         'content': 'required',
//       });
//
//       // Bind the data
//       await context.bind(data);
//
//       final newId = (await repository.getAll()).length + 1;
//       final post = Post(
//         id: newId.toString(),
//         title: data['title'] as String,
//         content: data['content'] as String,
//       );
//
//       await repository.add(post);
//
//       context.response.statusCode = 201;
//       context.json({
//         'id': post.id,
//         'title': post.title,
//         'content': post.content,
//         'createdAt': post.createdAt.toIso8601String(),
//       });
//     } catch (e) {
//       if (e is ValidationError) {
//         context.response.statusCode = 400;
//         context.json({'errors': e.errors});
//       } else {
//         context.response.statusCode = 400;
//         context.json({'error': 'Invalid request: ${e.toString()}'});
//       }
//     }
//   }
// }
//
// class PostUpdateView extends View {
//   final PostRepository repository;
//
//   PostUpdateView(this.repository);
//
//   @override
//   List<String> get allowedMethods => ['PUT', 'PATCH'];
//
//   @override
//   Future<void> put(EngineContext context) async {
//     await _updatePost(context, fullUpdate: true);
//   }
//
//   @override
//   Future<void> patch(EngineContext context) async {
//     await _updatePost(context, fullUpdate: false);
//   }
//
//   Future<void> _updatePost(EngineContext context,
//       {required bool fullUpdate}) async {
//     try {
//       final id = context.param('id');
//       if (id == null) {
//         context.response.statusCode = 400;
//         context.json({'error': 'Post ID is required'});
//         return;
//       }
//
//       final existingPost = await repository.getById(id);
//       if (existingPost == null) {
//         context.response.statusCode = 404;
//         context.json({'error': 'Post not found'});
//         return;
//       }
//
//       final data = <String, dynamic>{};
//
//       // For full updates, require all fields
//       if (fullUpdate) {
//         await context.validate({
//           'title': 'required',
//           'content': 'required',
//         });
//       }
//
//       // Bind the data
//       await context.bind(data);
//
//       final updatedPost = Post(
//         id: existingPost.id,
//         title: data.containsKey('title')
//             ? data['title'] as String
//             : existingPost.title,
//         content: data.containsKey('content')
//             ? data['content'] as String
//             : existingPost.content,
//         createdAt: existingPost.createdAt,
//       );
//
//       final success = await repository.update(updatedPost);
//
//       if (success) {
//         context.json({
//           'id': updatedPost.id,
//           'title': updatedPost.title,
//           'content': updatedPost.content,
//           'createdAt': updatedPost.createdAt.toIso8601String(),
//         });
//       } else {
//         context.response.statusCode = 500;
//         context.json({'error': 'Failed to update post'});
//       }
//     } catch (e) {
//       if (e is ValidationError) {
//         context.response.statusCode = 400;
//         context.json({'errors': e.errors});
//       } else {
//         context.response.statusCode = 400;
//         context.json({'error': 'Invalid request: ${e.toString()}'});
//       }
//     }
//   }
// }
//
// class PostDeleteView extends View {
//   final PostRepository repository;
//
//   PostDeleteView(this.repository);
//
//   @override
//   List<String> get allowedMethods => ['DELETE'];
//
//   @override
//   Future<void> delete(EngineContext context) async {
//     try {
//       final id = context.param('id');
//       if (id == null) {
//         context.response.statusCode = 400;
//         context.json({'error': 'Post ID is required'});
//         return;
//       }
//
//       final success = await repository.delete(id);
//
//       if (success) {
//         context.abortWithStatus(204);
//       } else {
//         context.response.statusCode = 404;
//         context.json({'error': 'Post not found'});
//       }
//     } catch (e) {
//       context.response.statusCode = 500;
//       context.json({'error': 'Server error: ${e.toString()}'});
//     }
//   }
// }
//
// class CommentCreateView extends View {
//   final CommentRepository repository;
//
//   CommentCreateView(this.repository);
//
//   @override
//   List<String> get allowedMethods => ['POST'];
//
//   @override
//   Future<void> post(EngineContext context) async {
//     try {
//       final postId = context.param('postId');
//       if (postId == null) {
//         context.response.statusCode = 400;
//         context.json({'error': 'Post ID is required'});
//         return;
//       }
//
//       final data = <String, dynamic>{};
//
//       // Validate required fields
//       await context.validate({
//         'author': 'required',
//         'content': 'required',
//       });
//
//       // Bind the data
//       await context.bind(data);
//
//       final comments = await repository.getByPostId(postId);
//       final newId = (comments.length + 1).toString();
//
//       final comment = Comment(
//         id: newId,
//         postId: postId,
//         author: data['author'] as String,
//         content: data['content'] as String,
//       );
//
//       await repository.add(comment);
//
//       context.response.statusCode = 201;
//       context.json({
//         'id': comment.id,
//         'postId': comment.postId,
//         'author': comment.author,
//         'content': comment.content,
//         'createdAt': comment.createdAt.toIso8601String(),
//       });
//     } catch (e) {
//       if (e is ValidationError) {
//         context.response.statusCode = 400;
//         context.json({'errors': e.errors});
//       } else {
//         context.response.statusCode = 400;
//         context.json({'error': 'Invalid request: ${e.toString()}'});
//       }
//     }
//   }
// }
//
// // Admin dashboard view
// class AdminDashboardView extends View {
//   final PostRepository postRepository;
//   final CommentRepository commentRepository;
//
//   AdminDashboardView(this.postRepository, this.commentRepository);
//
//   @override
//   List<String> get allowedMethods => ['GET'];
//
//   @override
//   Future<void> get(EngineContext context) async {
//     // Check if user is admin (would be set by auth middleware)
//     final user = context.getContextData('user') as Map<String, dynamic>?;
//     if (user == null) {
//       context.response.statusCode = 401;
//       context.json({'error': 'Unauthorized'});
//       return;
//     }
//
//     final posts = await postRepository.getAll();
//     final allComments = <Comment>[];
//
//     for (final post in posts) {
//       final comments = await commentRepository.getByPostId(post.id);
//       allComments.addAll(comments);
//     }
//
//     context.json({
//       'stats': {
//         'totalPosts': posts.length,
//         'totalComments': allComments.length,
//         'commentsPerPost':
//             posts.isEmpty ? 0 : allComments.length / posts.length,
//       },
//       'recentPosts': posts
//           .take(5)
//           .map((post) => {
//                 'id': post.id,
//                 'title': post.title,
//                 'createdAt': post.createdAt.toIso8601String(),
//               })
//           .toList(),
//     });
//   }
// }
//
// void main() async {
//   // Create repositories
//   final postRepository = PostRepository();
//   final commentRepository = CommentRepository();
//
//   // Create engine and router
//   final engine = Engine();
//   final router = Router();
//
//   // Public API routes
//   router
//       .group(
//         path: '/api',
//         builder: (api) {
//           // Posts
//           api.view('/posts', PostListView(postRepository)).name('posts.list');
//           api
//               .view('/posts/{id}',
//                   PostDetailView(postRepository, commentRepository))
//               .name('posts.detail');
//           api
//               .view('/posts', PostCreateView(postRepository))
//               .name('posts.create');
//           api
//               .view('/posts/{id}', PostUpdateView(postRepository))
//               .name('posts.update');
//           api
//               .view('/posts/{id}', PostDeleteView(postRepository))
//               .name('posts.delete');
//
//           // Comments
//           api
//               .view('/posts/{postId}/comments',
//                   CommentCreateView(commentRepository))
//               .name('comments.create');
//         },
//       )
//       .name('api');
//
//   // Admin routes with authentication
//   router
//       .group(
//         path: '/admin',
//         middlewares: [authMiddleware],
//         builder: (admin) {
//           admin
//               .view('/dashboard',
//                   AdminDashboardView(postRepository, commentRepository))
//               .name('dashboard');
//         },
//       )
//       .name('admin');
//
//   // Mount router
//   engine.use(router);
//
//   engine.serve();
// }
