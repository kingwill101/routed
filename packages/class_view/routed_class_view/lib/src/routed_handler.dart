import 'package:class_view/class_view.dart';
import 'package:routed/routed.dart' as routed;

import 'routed_adapter.dart';

/// Handler functions for integrating class views with Routed
class RoutedViewHandler {
  /// Create a Routed handler from a view factory function
  ///
  /// Usage:
  /// ```dart
  /// final router = Router();
  /// router.get('/posts', RoutedViewHandler.handle(() => PostListView()));
  /// router.get('/posts/<id>', RoutedViewHandler.handle((ctx) => PostDetailView()));
  /// ```
  static routed.Handler handle(View Function() viewFactory) {
    return (routed.EngineContext context) async {
      // Create the view and adapter
      final view = viewFactory();
      final adapter = RoutedAdapter(context);

      try {
        // Set up the view with the adapter
        view.setAdapter(adapter);

        // Set up the view
        await adapter.setup();
        // Dispatch the request
        await view.dispatch();
      } catch (e, stackTrace) {
        // Handle any errors that weren't caught by the view
        await view.handleError(e, stackTrace);
      } finally {
        await adapter.teardown();
      }
      return context.response;
    };
  }

  /// Create a handler for a specific view instance
  ///
  /// Usage:
  /// ```dart
  /// final myView = PostListView();
  /// router.get('/posts', RoutedViewHandler.handleInstance(myView));
  /// ```
  static routed.Handler handleInstance(View view) {
    return (routed.EngineContext context) async {
      final adapter = RoutedAdapter(context);

      try {
        view.setAdapter(adapter);
        await adapter.setup();
        await view.dispatch();
        await adapter.teardown();
      } catch (e, stackTrace) {
        await view.handleError(e, stackTrace);
        await adapter.teardown();
      }
      return context.response;
    };
  }
}

/// Extension methods to make Router integration easier
extension RouterExtensions on routed.Router {
  /// Add a class view to the router with GET method
  routed.RouteBuilder getView(String route, View Function() viewFactory) {
    return get(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with POST method
  routed.RouteBuilder postView(String route, View Function() viewFactory) {
    return post(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with PUT method
  routed.RouteBuilder putView(String route, View Function() viewFactory) {
    return put(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with DELETE method
  routed.RouteBuilder deleteView(String route, View Function() viewFactory) {
    return delete(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view that handles multiple HTTP methods
  routed.RouteBuilder allView(String route, View Function() viewFactory) {
    return any(route, RoutedViewHandler.handle(viewFactory));
  }
}

/// Extension methods to make Router integration easier
extension EngineExtensions on routed.Engine {
  /// Add a class view to the router with GET method
  routed.RouteBuilder getView(String route, View Function() viewFactory) {
    return get(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with POST method
  routed.RouteBuilder postView(String route, View Function() viewFactory) {
    return post(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with PUT method
  routed.RouteBuilder putView(String route, View Function() viewFactory) {
    return put(route, RoutedViewHandler.handle(viewFactory));
  }

  /// Add a class view to the router with DELETE method
  routed.RouteBuilder deleteView(String route, View Function() viewFactory) {
    return delete(route, RoutedViewHandler.handle(viewFactory));
  }
}
