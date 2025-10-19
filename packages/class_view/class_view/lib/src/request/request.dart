import '../adapter/view_adapter.dart';
import '../view/form/fields/file.dart' show FormFile;

/// Laravel-style request object for convenient request data access
///
/// Provides a clean, expressive API for accessing request data:
/// ```dart
/// // Parameter access
/// final name = request().get('name', 'Anonymous');
/// final email = request().input('email');
/// final search = request().query('search');
///
/// // Data collection
/// final data = request().all();
/// final subset = request().only(['name', 'email']);
/// final filtered = request().except(['password']);
///
/// // Validation helpers
/// if (request().filled('email')) {
///   // Process email
/// }
///
/// if (request().missing('required_field')) {
///   // Handle missing field
/// }
///
/// // Request type checking
/// if (request().isMethod('POST')) {
///   // Handle POST
/// }
///
/// if (request().ajax()) {
///   // Handle AJAX request
/// }
/// ```
class Request {
  final ViewAdapter _adapter;

  Request(this._adapter);

  // === Parameter Access ===

  /// Get a parameter by name with optional default value
  ///
  /// Checks both route parameters and query parameters
  Future<String?> get(String key, [String? defaultValue]) async {
    return await _adapter.getParam(key) ?? defaultValue;
  }

  /// Alias for get() - Laravel compatibility
  Future<String?> input(String key, [String? defaultValue]) async {
    return await get(key, defaultValue);
  }

  /// Get query parameter only
  Future<String?> query(String key, [String? defaultValue]) async {
    final queryParams = await _adapter.getQueryParams();
    return queryParams[key] ?? defaultValue;
  }

  /// Get route parameter only
  Future<String?> route(String key, [String? defaultValue]) async {
    final routeParams = await _adapter.getRouteParams();
    return routeParams[key] ?? defaultValue;
  }

  // === Data Collection ===

  /// Get all parameters (route + query)
  Future<Map<String, String>> all() async {
    return await _adapter.getParams();
  }

  /// Get only specified parameters
  Future<Map<String, String>> only(List<String> keys) async {
    final allParams = await _adapter.getParams();
    return Map.fromEntries(
      allParams.entries.where((entry) => keys.contains(entry.key)),
    );
  }

  /// Get all parameters except specified ones
  Future<Map<String, String>> except(List<String> keys) async {
    final allParams = await _adapter.getParams();
    return Map.fromEntries(
      allParams.entries.where((entry) => !keys.contains(entry.key)),
    );
  }

  // === Validation Helpers ===

  /// Check if parameter exists and has non-empty value
  Future<bool> filled(String key) async {
    final value = await _adapter.getParam(key);
    return value != null && value.isNotEmpty;
  }

  /// Check if parameter is missing
  Future<bool> missing(String key) async {
    final params = await _adapter.getParams();
    return !params.containsKey(key);
  }

  /// Check if parameter exists (even if empty)
  Future<bool> has(String key) async {
    final params = await _adapter.getParams();
    return params.containsKey(key);
  }

  // === Request Information ===

  /// Get HTTP method
  Future<String> getMethod() async => await _adapter.getMethod();

  /// Get request URI
  Future<Uri> getUri() async => await _adapter.getUri();

  /// Check if request method matches
  Future<bool> isMethod(String method) async {
    final currentMethod = await _adapter.getMethod();
    print('isMethod($method) called with currentMethod: $currentMethod');
    final result = currentMethod.toUpperCase() == method.toUpperCase();
    print('isMethod($method) returning: $result');
    return result;
  }

  /// Check if request is AJAX
  Future<bool> ajax() async {
    final requestedWith = await _adapter.getHeader('x-requested-with');
    return requestedWith?.toLowerCase() == 'xmlhttprequest';
  }

  /// Check if request expects JSON response
  Future<bool> expectsJson() async {
    final accept = await _adapter.getHeader('accept') ?? '';
    return accept.contains('application/json') || await ajax();
  }

  /// Check if request content is JSON
  Future<bool> isJson() async {
    final contentType = await _adapter.getHeader('content-type') ?? '';
    return contentType.contains('application/json');
  }

  // === Headers ===

  /// Get all headers
  Future<Map<String, String>> headers() async {
    return await _adapter.getHeaders();
  }

  /// Get specific header
  Future<String?> header(String name) async {
    return await _adapter.getHeader(name);
  }

  /// Get user agent
  Future<String?> userAgent() async {
    return await _adapter.getHeader('user-agent');
  }

  /// Get bearer token from Authorization header
  Future<String?> bearerToken() async {
    final auth = await _adapter.getHeader('authorization');
    if (auth != null && auth.startsWith('Bearer ')) {
      return auth.substring(7);
    }
    return null;
  }

  // === Body Data ===

  /// Get raw request body
  Future<String> body() => _adapter.getBody();

  /// Get JSON body
  Future<Map<String, dynamic>> json() => _adapter.getJsonBody();

  /// Get form data
  Future<Map<String, dynamic>> form() => _adapter.getFormData();

  // === File Operations ===

  /// Get an uploaded file by field name
  Future<FormFile?> file(String fieldName) =>
      _adapter.getUploadedFile(fieldName);

  /// Get all uploaded files
  Future<List<FormFile>> files() => _adapter.getUploadedFiles();

  /// Check if a file was uploaded for the given field
  Future<bool> hasFile(String fieldName) => _adapter.hasFile(fieldName);

  // === Convenience Methods ===

  /// Get request data based on content type
  Future<Map<String, dynamic>> data() async {
    if (await isJson()) {
      return await json();
    } else {
      return await form();
    }
  }

  // === Type Checking Properties ===

  Future<bool> get isGet async => await isMethod('GET');

  Future<bool> get isPost async => await isMethod('POST');

  Future<bool> get isPut async => await isMethod('PUT');

  Future<bool> get isDelete async => await isMethod('DELETE');

  Future<bool> get isPatch async => await isMethod('PATCH');

  Future<bool> get isHead async => await isMethod('HEAD');

  Future<bool> get isOptions async => await isMethod('OPTIONS');
}
