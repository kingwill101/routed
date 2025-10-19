/// Shelf adapter for class_view
///
/// This library provides integration between class_view and the Shelf framework.
/// It includes adapters, handlers, and utilities to make it easy to use
/// class-based views with Shelf and Shelf Router.
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:shelf/shelf.dart';
/// import 'package:shelf_router/shelf_router.dart';
/// import 'package:shelf_class_view/shelf_class_view.dart';
///
/// // Create your views
/// class PostListView extends ListView<Post> {
///   @override
///   Future<({List<Post> items, int total})> getObjectList({int page = 1, int pageSize = 10}) async {
///     return await PostRepository.findAll(page: page, pageSize: pageSize);
///   }
/// }
///
/// class PostDetailView extends DetailView<Post> {
///   @override
///   Future<Post?> getObject() async {
///     final id = getParam('id');
///     return await PostRepository.findById(id);
///   }
/// }
///
/// // Set up your router
/// final router = Router();
///
/// // Method 1: Using extension methods (easiest)
/// router.getView('/posts', () => PostListView());
/// router.getView('/posts/<id>', () => PostDetailView());
///
/// // Method 2: Using handlers directly
/// router.get('/posts', ShelfViewHandler.handle(() => PostListView()));
/// router.get('/posts/<id>', ShelfViewHandler.handle(() => PostDetailView()));
///
/// // Start your server
/// final server = await io.serve(router, 'localhost', 8080);
/// ```
///
/// ## Features
///
/// - **ShelfAdapter**: Implements ViewAdapter for Shelf Request/Response
/// - **ShelfViewHandler**: Utilities for creating Shelf handlers from views
/// - **Router Extensions**: Convenient methods for adding views to routers
/// - **Automatic Parameter Extraction**: Route parameters are automatically available
/// - **Error Handling**: Proper error handling and response generation
///
library;

export 'shelf_adapter.dart';
export 'shelf_handler.dart';
