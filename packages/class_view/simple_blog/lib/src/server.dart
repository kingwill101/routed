import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'views/api/newsletter_view.dart';
import 'views/api/post_create_view.dart';
import 'views/api/post_delete_view.dart';
import 'views/api/post_detail_view.dart';

// API views (JSON responses)
import 'views/api/post_list_view.dart';
import 'views/api/post_update_view.dart';
import 'views/api/widget_showcase_view.dart';

// Web views (HTML template responses)
import 'views/web/home_view.dart';
import 'views/web/post_detail_view.dart';
import 'views/web/post_form_view.dart';
import 'views/web/post_list_view.dart';
import 'views/web/widget_showcase_view.dart';

/// Create the Shelf handler with all routes
shelf.Handler createHandler() {
  final router = Router();

  // Static files
  final staticHandler = createStaticHandler(
    'web',
    defaultDocument: 'index.html',
  );

  // Web routes (HTML responses)

  // Home page
  router.getView('/', () => WebHomeView());

  // Post list with search and pagination
  router.getView('/posts', () => WebPostListView());

  // Create new post
  router.getView('/posts/new', () => WebPostCreateView());
  router.postView('/posts/new', () => WebPostCreateView());

  // Post detail by slug
  router.getView('/posts/<slug>', () => WebPostDetailView());

  // Edit post
  router.getView('/posts/<id>/edit', () => WebPostEditView());
  router.postView('/posts/<id>/edit', () => WebPostEditView());

  // Widget showcase (web form demo)
  router.getView('/widgets', () => WebWidgetShowcaseView());
  router.postView('/widgets', () => WebWidgetShowcaseView());

  // API routes (JSON responses)

  // List all posts (with search and pagination)
  router.getView('/api/posts', () => PostListView());

  // Create new post (GET for form info, POST for creation)
  router.getView('/api/posts/new', () => PostCreateView());
  router.postView('/api/posts', () => PostCreateView());

  // Post detail by slug
  router.getView('/api/posts/<slug>', () => PostDetailView());

  // Edit post (GET for form info, PUT for update)
  router.getView('/api/posts/<id>/edit', () => PostUpdateView());
  router.putView('/api/posts/<id>', () => PostUpdateView());

  // Delete post (GET for confirmation, DELETE for deletion)
  router.getView('/api/posts/<id>/delete', () => PostDeleteView());
  router.deleteView('/api/posts/<id>', () => PostDeleteView());

  // Newsletter API routes
  router.getView('/api/newsletter', () => NewsletterView());
  router.postView('/api/newsletter', () => NewsletterView());
  router.getView('/api/newsletter/stats', () => NewsletterView());
  router.deleteView('/api/newsletter/<email>', () => NewsletterView());

  // Widget Showcase - Interactive form field catalog
  router.getView('/api/widgets', () => WidgetShowcaseView());
  router.postView('/api/widgets', () => WidgetShowcaseView());

  // Health check endpoint
  router.get('/health', (shelf.Request request) {
    return shelf.Response.ok('SimpleBlog is running!');
  });

  // Fallback to static files
  router.get('/<path|.*>', staticHandler);

  // Create pipeline with middleware
  final pipeline = shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(errorHandler())
      .addHandler(router.call);

  return pipeline;
}

/// CORS middleware
shelf.Middleware corsHeaders() {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      final response = await innerHandler(request);

      return response.change(
        headers: {
          ...response.headers,
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers':
              'Origin, Content-Type, Accept, Authorization',
        },
      );
    };
  };
}

/// Error handling middleware
shelf.Middleware errorHandler() {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      try {
        return await innerHandler(request);
      } catch (error, stackTrace) {
        print('Error handling request: $error');
        print('Stack trace: $stackTrace');

        // Determine expected response type based on:
        // 1. Route prefix (api/)
        // 2. Accept header preferring JSON explicitly
        // 3. Content-Type of request (for POST/PUT)
        final acceptHeader = request.headers['accept'] ?? '';
        final contentTypeHeader = request.headers['content-type'] ?? '';

        final isApiRequest =
            request.url.path.startsWith('api/') ||
            // Explicit JSON preference (and not also accepting HTML)
            (acceptHeader.contains('application/json') &&
                !acceptHeader.contains('text/html')) ||
            // Request sent JSON content
            contentTypeHeader.contains('application/json');

        if (isApiRequest) {
          return shelf.Response.internalServerError(
            body:
                '{"error": "Internal server error", "message": "${error.toString()}"}',
            headers: {'content-type': 'application/json'},
          );
        } else {
          return shelf.Response.internalServerError(
            body: 'Internal Server Error\n\nError: ${error.toString()}',
          );
        }
      }
    };
  };
}

/// Start the server
Future<void> startServer({int port = 8080}) async {
  // Load SimpleBlog templates and configure TemplateManager
  TemplateManager.configure(
    templateDirectory: 'templates',
    cacheTemplates: false,
  );

  final handler = createHandler();

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

  print(
    'SimpleBlog server running on http://${server.address.host}:${server.port}',
  );
  print('');
  print('Available web endpoints:');
  print('  GET    /                    - Home page');
  print('  GET    /posts               - List all posts');
  print('  GET    /posts/new           - New post form');
  print('  POST   /posts/new           - Create post');
  print('  GET    /posts/<slug>        - View post');
  print('  GET    /posts/<id>/edit     - Edit post form');
  print('  POST   /posts/<id>/edit     - Update post');
  print('');
  print('API endpoints:');
  print('  GET    /api/posts           - List posts (JSON)');
  print('  POST   /api/posts           - Create post (JSON)');
  print('  GET    /api/posts/<slug>    - Get post (JSON)');
  print('  PUT    /api/posts/<id>      - Update post (JSON)');
  print('  DELETE /api/posts/<id>      - Delete post (JSON)');
  print('  GET    /api/newsletter      - Newsletter API info (JSON)');
  print('  POST   /api/newsletter      - Subscribe to newsletter (JSON)');
  print('  GET    /api/newsletter/stats - Newsletter statistics (JSON)');
  print(
    '  DELETE /api/newsletter/<email> - Unsubscribe from newsletter (JSON)',
  );
  print('');
  print('Try:');
  print('  curl http://localhost:$port/');
  print('  curl http://localhost:$port/api/posts');
  print('  curl -X POST http://localhost:$port/api/posts \\');
  print('       -H "Content-Type: application/json" \\');
  print(
    '       -d \'{"title":"My Post","content":"Hello World","author":"Me"}\'',
  );
  print('  curl -X POST http://localhost:$port/api/newsletter \\');
  print('       -H "Content-Type: application/json" \\');
  print('       -d \'{"email":"test@example.com","name":"Test User"}\'');
}
