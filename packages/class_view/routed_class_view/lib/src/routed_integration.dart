/// Routed adapter for class_view
///
/// This library provides integration between class_view and the Routed framework.
/// It includes adapters, handlers, and utilities to make it easy to use
/// class-based views with Routed.
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:routed/routed.dart';
/// import 'package:routed_class_view/routed_class_view.dart';
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
/// router.get('/posts', RoutedViewHandler.handle(() => PostListView()));
/// router.get('/posts/<id>', RoutedViewHandler.handle(() => PostDetailView()));
///
/// // Start your server
/// await Engine().run();
/// ```
///
/// ## Features
///
/// - **RoutedAdapter**: Implements ViewAdapter for Routed EngineContext
/// - **RoutedViewHandler**: Utilities for creating Routed handlers from views
/// - **Router Extensions**: Convenient methods for adding views to routers
/// - **Automatic Parameter Extraction**: Route parameters are automatically available
/// - **Error Handling**: Proper error handling and response generation
///
library;

export 'routed_adapter.dart';
export 'routed_handler.dart';
