import '../view/form/fields/file.dart' show FormFile;

/// Framework-agnostic adapter interface for class views
///
/// This interface provides a clean, consistent API that adapters must implement
/// to bridge between framework-specific contexts and views. All methods are
/// async for consistency and to support various framework patterns.
///
/// ## Available Adapters
///
/// - `shelf`: For the shelf package
/// - `routed`: For the routed package
abstract class ViewAdapter {
  /// HTTP method for current request (e.g., 'GET', 'POST', 'PUT', 'DELETE')
  Future<String> getMethod();

  /// Request URI including path, query parameters, and scheme
  Future<Uri> getUri();

  /// Get a parameter by name from either route parameters or query parameters
  ///
  /// This method searches for the parameter in both route parameters and query
  /// parameters. If the same parameter name exists in both, the route parameter
  /// takes precedence.
  ///
  /// Example:
  /// - Route: `/users/{id}/posts?filter=active`
  /// - `getParam('id')` returns the route parameter value
  /// - `getParam('filter')` returns the query parameter value
  Future<String?> getParam(String name);

  /// Get all parameters from both route and query parameters combined
  ///
  /// Returns a map containing all parameters from both route and query parameters.
  /// If a parameter exists in both route and query parameters, the route parameter
  /// takes precedence.
  ///
  /// Example:
  /// - Route: `/users/{id}/posts?filter=active&id=789`
  /// - Returns: `{'id': '123', 'filter': 'active'}`
  ///   (route param 'id' takes precedence over query param)
  Future<Map<String, String>> getParams();

  /// Get query parameters only from the URL query string
  ///
  /// Returns a map containing only the query parameters from the URL query string.
  /// Does not include any route parameters.
  ///
  /// Example:
  /// - URL: `/users?filter=active&sort=date`
  /// - Returns: `{'filter': 'active', 'sort': 'date'}`
  Future<Map<String, String>> getQueryParams();

  /// Get route parameters only from the URL path
  ///
  /// Returns a map containing only the route parameters from the URL path.
  /// Does not include any query parameters.
  ///
  /// Example:
  /// - Route: `/users/{id}/posts/{postId}`
  /// - URL: `/users/123/posts/456`
  /// - Returns: `{'id': '123', 'postId': '456'}`
  Future<Map<String, String>> getRouteParams();

  /// Get all request headers
  ///
  /// Returns a map containing all request headers. Header names are converted
  /// to lowercase for consistency.
  ///
  /// Example:
  /// - Returns: `{'content-type': 'application/json', 'authorization': 'Bearer token'}`
  Future<Map<String, String>> getHeaders();

  /// Get a specific header value by name
  ///
  /// Returns the value of the specified header, or null if the header doesn't exist.
  /// Header name matching is case-insensitive.
  ///
  /// Example:
  /// - `getHeader('content-type')` returns `'application/json'`
  Future<String?> getHeader(String name);

  /// Get request body as raw string
  ///
  /// Returns the complete request body as a string, regardless of content type.
  /// For JSON or form data, consider using [getJsonBody] or [getFormData] instead.
  Future<String> getBody();

  /// Get request body parsed as JSON
  ///
  /// Parses the request body as JSON and returns it as a map.
  /// Throws an error if the body is not valid JSON.
  ///
  /// Example:
  /// - Body: `{"name": "John", "age": 30}`
  /// - Returns: `{'name': 'John', 'age': 30}`
  Future<Map<String, dynamic>> getJsonBody();

  /// Get form data from request
  ///
  /// Parses the request body as form data and returns it as a map.
  /// Handles both application/x-www-form-urlencoded and multipart/form-data.
  ///
  /// Example:
  /// - Body: `name=John&age=30`
  /// - Returns: `{'name': 'John', 'age': '30'}`
  Future<Map<String, dynamic>> getFormData();

  // === File Operations ===

  /// Get an uploaded file by field name
  ///
  /// Returns the uploaded file for the specified field name, or null if no file
  /// was uploaded for that field. Only works with multipart/form-data requests.
  ///
  /// Example:
  /// - Form field: `file=@document.pdf`
  /// - `getUploadedFile('file')` returns the file object
  Future<FormFile?> getUploadedFile(String fieldName);

  /// Get all uploaded files
  ///
  /// Returns a list of all files uploaded in the request.
  /// Only works with multipart/form-data requests.
  ///
  /// Example:
  /// - Form fields: `file1=@doc1.pdf&file2=@doc2.pdf`
  /// - Returns: `[FormFile('file1', ...), FormFile('file2', ...)]`
  Future<List<FormFile>> getUploadedFiles();

  /// Check if a file was uploaded for the given field
  ///
  /// Returns true if a file was uploaded for the specified field name.
  /// Only works with multipart/form-data requests.
  ///
  /// Example:
  /// - Form field: `file=@document.pdf`
  /// - `hasFile('file')` returns `true`
  Future<bool> hasFile(String fieldName);

  // === Response Operations ===

  /// Set the status code for the response
  ///
  /// Sets the HTTP status code for the response.
  /// Example: `setStatusCode(201)` for Created
  Future<void> setStatusCode(int code);

  /// Set a header for the response
  ///
  /// Sets a single header value for the response.
  /// Example: `setHeader('Content-Type', 'application/json')`
  Future<void> setHeader(String name, String value);

  /// Write to the response body
  ///
  /// Writes a string to the response body. Can be called multiple times
  /// to append content.
  /// Example: `write('Hello, ')` followed by `write('World!')`
  Future<void> write(String body);

  /// Write JSON data to response
  ///
  /// Converts the data to JSON and writes it to the response body.
  /// Automatically sets Content-Type to application/json.
  ///
  /// Example:
  /// ```dart
  /// writeJson({
  ///   'message': 'Success',
  ///   'data': {'id': 123}
  /// }, statusCode: 201);
  /// ```
  Future<void> writeJson(Map<String, dynamic> data, {int statusCode = 200});

  /// Redirect to a URL
  ///
  /// Sends a redirect response to the specified URL.
  /// Default status code is 302 (Found), but can be changed to 301 (Moved Permanently)
  /// or other redirect status codes.
  ///
  /// Example: `redirect('/new-location', statusCode: 301)`
  Future<void> redirect(String url, {int statusCode = 302});

  // === Lifecycle ===

  /// Setup the adapter for request processing
  ///
  /// Called before processing the request. Use this to initialize any
  /// framework-specific context or state needed for the request.
  Future<void> setup();

  /// Cleanup after request processing
  ///
  /// Called after the request has been processed. Use this to clean up any
  /// resources or state created during request processing.
  Future<void> teardown();
}
