import 'package:class_view/class_view.dart' hide Request;
import 'package:shelf/shelf.dart' show Request, Handler;
import 'package:shelf_router/shelf_router.dart';

import 'shelf_adapter.dart';

/// Handler functions for integrating class views with Shelf
class ShelfViewHandler {
  /// Create a Shelf handler from a view factory function
  ///
  /// Usage:
  /// ```dart
  /// final router = Router();
  /// router.get('/posts', ShelfViewHandler.handle(() => PostListView()));
  /// router.get('/posts/<id>', ShelfViewHandler.handle(() => PostDetailView()));
  /// ```
  static Handler handle(View Function() viewFactory) {
    return (Request request) async {
      // Extract route parameters using the centralized function
      final routeParams = _extractRouteParams(request);

      // Create the view and adapter
      final view = viewFactory();
      final adapter = ShelfAdapter.fromRequest(request, routeParams);

      try {
        // Set up the view with the adapter
        view.setAdapter(adapter);

        // Dispatch the request
        await view.dispatch();

        // Return the response
        return adapter.buildResponse();
      } catch (e, stackTrace) {
        // Handle any errors that weren't caught by the view
        await view.handleError(e, stackTrace);
        return adapter.buildResponse();
      }
    };
  }

  /// Create a handler with automatic route parameter extraction
  ///
  /// This version automatically extracts route parameters from the Shelf request context
  /// and passes them to the adapter.
  static Handler handleWithParams(
    View Function(Map<String, String> params) viewFactory,
  ) {
    return (Request request) async {
      // Extract route parameters
      final routeParams = _extractRouteParams(request);

      // Create the view and adapter
      final view = viewFactory(routeParams);
      final adapter = ShelfAdapter.fromRequest(request, routeParams);

      try {
        view.setAdapter(adapter);
        await view.dispatch();
        return adapter.buildResponse();
      } catch (e, stackTrace) {
        await view.handleError(e, stackTrace);
        return adapter.buildResponse();
      }
    };
  }

  /// Create a handler for a specific view instance
  ///
  /// Usage:
  /// ```dart
  /// final myView = PostListView();
  /// router.get('/posts', ShelfViewHandler.handleInstance(myView));
  /// ```
  static Handler handleInstance(View view) {
    return (Request request) async {
      final routeParams = _extractRouteParams(request);
      final adapter = ShelfAdapter.fromRequest(request, routeParams);

      try {
        view.setAdapter(adapter);
        await view.dispatch();
        return adapter.buildResponse();
      } catch (e, stackTrace) {
        await view.handleError(e, stackTrace);
        return adapter.buildResponse();
      }
    };
  }

  /// Extract route parameters from Shelf request context
  static Map<String, String> _extractRouteParams(Request request) {
    final routeParams = <String, String>{};
    final context = request.context;

    // Check various ways Shelf router might store parameters
    if (context.containsKey('shelf_router/params')) {
      final params = context['shelf_router/params'];
      if (params is Map<String, String>) {
        routeParams.addAll(params);
      }
    }

    // Also check for parameters in the URL path segments
    // This is a fallback for manual parameter extraction
    return routeParams;
  }
}

/// Extension methods to make Router integration even easier
extension RouterExtensions on Router {
  /// Add a class view to the router with GET method
  void getView(String route, View Function() viewFactory) {
    get(route, ShelfViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with POST method
  void postView(String route, View Function() viewFactory) {
    post(route, ShelfViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with PUT method
  void putView(String route, View Function() viewFactory) {
    put(route, ShelfViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with DELETE method
  void deleteView(String route, View Function() viewFactory) {
    delete(route, ShelfViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router that handles multiple HTTP methods
  void allView(String route, View Function() viewFactory) {
    all(route, ShelfViewHandler.handle(viewFactory));
  }

  /// Add a class view with automatic route parameter extraction
  void getViewWithParams(
    String route,
    View Function(Map<String, String> params) viewFactory,
  ) {
    get(route, ShelfViewHandler.handleWithParams(viewFactory));
  }

  /// Add a POST view with automatic route parameter extraction
  void postViewWithParams(
    String route,
    View Function(Map<String, String> params) viewFactory,
  ) {
    post(route, ShelfViewHandler.handleWithParams(viewFactory));
  }
}
