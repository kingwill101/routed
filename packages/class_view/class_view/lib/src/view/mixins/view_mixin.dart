import 'dart:io' show HttpStatus;

import '../../adapter/view_adapter.dart';
import '../../request/request.dart';
import '../../response/response.dart';
import '../base_views/base.dart';

/// Base mixin for all views, providing core request handling and response capabilities
mixin ViewMixin {
  /// The server adapter for request/response operations.
  ViewAdapter? _adapter;

  /// Set the server adapter.
  void setAdapter(ViewAdapter adapter) {
    _adapter = adapter;
  }

  /// Get the adapter with null check
  ViewAdapter get adapter {
    if (_adapter == null) {
      throw StateError('No adapter set. Call setAdapter() first.');
    }
    return _adapter!;
  }

  /// List of HTTP methods this view allows
  List<String> get allowedMethods => ['GET'];

  /// Get the HTTP method of the current request
  Future<String> getMethod() => adapter.getMethod();

  /// Get URI of the current request
  Future<Uri> getUri() => adapter.getUri();

  /// Called before handling the request
  Future<void> setup() async => await adapter.setup();

  /// Called after handling the request
  Future<void> teardown() async => await adapter.teardown();

  /// Called before dispatching to the handler method
  Future<void> beforeDispatch() async {}

  /// Called after dispatching to the handler method
  Future<void> afterDispatch() async {}

  /// Dispatch the request to the appropriate method handler
  Future<void> dispatch();

  /// Handle errors that occur during request processing
  Future<void> handleError(Object error, [StackTrace? stackTrace]);

  /// Handle GET requests
  Future<void> get();

  /// Handle POST requests
  Future<void> post();

  /// Handle PUT requests
  Future<void> put();

  /// Handle DELETE requests
  Future<void> delete();

  /// Handle PATCH requests
  Future<void> patch();

  /// Handle HEAD requests
  Future<void> head();

  /// Handle OPTIONS requests
  Future<void> options();

  // === Request Helper Methods ===

  /// Get a parameter by name from the request
  Future<String?> getParam(String name) => adapter.getParam(name);

  /// Get all parameters from the request
  Future<Map<String, String>> getParams() => adapter.getParams();

  /// Get query parameters only
  Future<Map<String, String>> getQueryParams() => adapter.getQueryParams();

  /// Get route parameters only
  Future<Map<String, String>> getRouteParams() => adapter.getRouteParams();

  /// Get request headers
  Future<Map<String, String>> getHeaders() => adapter.getHeaders();

  /// Get a specific header value
  Future<String?> getHeader(String name) => adapter.getHeader(name);

  /// Get request body as string
  Future<String> getBody() => adapter.getBody();

  /// Get request body parsed as JSON
  Future<Map<String, dynamic>> getJsonBody() => adapter.getJsonBody();

  /// Get form data from request
  Future<Map<String, dynamic>> getFormData() => adapter.getFormData();

  // === Response Helper Methods ===

  /// Get a Laravel-style request object for convenient request data access
  ///
  /// Provides clean, expressive syntax for accessing request data:
  /// ```dart
  /// // Parameter access with defaults
  /// final name = await request().get('name', 'Anonymous');
  /// final email = await request().input('email');
  /// final search = await request().query('search');
  ///
  /// // Data collection
  /// final allData = await request().all();
  /// final subset = await request().only(['name', 'email']);
  /// final filtered = await request().except(['password']);
  ///
  /// // Validation helpers
  /// if (await request().filled('email')) {
  ///   // Process email
  /// }
  ///
  /// if (await request().missing('required_field')) {
  ///   // Handle missing field
  /// }
  ///
  /// // Request type checking
  /// if (await request().isPost()) {
  ///   final data = await request().data(); // Auto-detects JSON vs form
  /// }
  ///
  /// if (await request().ajax()) {
  ///   // Handle AJAX request differently
  /// }
  ///
  /// // Header access
  /// final token = await request().bearerToken();
  /// final userAgent = await request().userAgent();
  ///
  /// // File uploads
  /// if (await request().hasFile('avatar')) {
  ///   final avatar = await request().file('avatar');
  ///   // Process uploaded file
  /// }
  ///
  /// final allFiles = await request().files();
  /// ```
  Request request() => Request(adapter);

  /// Get a Laravel-style response object for fluent response building
  ///
  /// Provides clean, expressive syntax for all response types with unified rendering:
  /// ```dart
  /// // HTML responses (perfect for Django-style forms)
  /// await response().html({@literal '<form>...</form>'});
  /// await response().view('template.html', data);  // Uses view's renderer/ViewEngine!
  ///
  /// // JSON responses for APIs
  /// await response().json({'data': items});
  ///
  /// // Redirects after form submission
  /// await response().redirect('/posts/1');
  ///
  /// // Fluent chaining with integrated rendering
  /// await response()
  ///   .status(422)
  ///   .header('Cache-Control', 'no-cache')
  ///   .view('form.html', {'errors': errors});  // Will use view's ViewEngine/Renderer
  /// ```
  ///
  /// The Response object automatically gets access to this view's rendering system:
  /// - If this is a View, it can access the view's ViewEngine/Renderer
  /// - Falls back gracefully through DefaultView system if no renderer configured
  Response response() {
    // Pass view context if this mixin is used on a View
    final view = (this is View) ? this as View : null;
    return Response(adapter, view);
  }

  /// Set the status code for the response
  Future<void> setStatusCode(int code) => adapter.setStatusCode(code);

  /// Set a header for the response
  Future<void> setHeader(String name, String value) =>
      adapter.setHeader(name, value);

  /// Write to the response body
  Future<void> write(String body) => adapter.write(body);

  /// Redirect to a URL
  Future<void> redirect(String url, {int statusCode = 302}) async {
    return await adapter.redirect(url, statusCode: statusCode);
  }

  /// Send a JSON response
  Future<void> sendJson(
    Map<String, dynamic> data, {
    int statusCode = HttpStatus.ok,
  }) async {
    return await adapter.writeJson(data, statusCode: statusCode);
  }
}
