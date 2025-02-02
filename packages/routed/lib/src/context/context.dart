import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/binding/multipart.dart';
import 'package:routed/src/binding/utils.dart';
import 'package:routed/src/engine/engine_template.dart';
import 'package:routed/src/file_handler.dart';
import 'package:routed/src/render/data_render.dart';
import 'package:routed/src/render/json_render.dart';
import 'package:routed/src/render/reader_render.dart';
import 'package:routed/src/render/redirect.dart';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/render/string_render.dart';
import 'package:routed/src/render/toml.dart';
import 'package:routed/src/render/xml.dart';
import 'package:routed/src/render/yaml.dart';

import '../render/html.dart';

part 'binding.dart';
part 'error.dart';
part 'render.dart';

/// The EngineContext is loosely inspired by gin.Context in Go.
/// It wraps [Request] and [Response], holds arbitrary keys/values,
/// tracks errors, and can control flow in a chain of handlers.
class EngineContext {
  /// The current HTTP request data.
  final Request request;

  /// The current HTTP response writer.
  final Response _response;

  /// Track errors that occur during request handling.
  /// Similar to gin.Context.Errors.
  final List<EngineError> _errors = [];

  /// Handlers chain, each of which can call `ctx.next()` or abort.
  List<Handler>? _handlers;

  /// Current index in the handler chain.
  int _index = -1;

  /// Indicates whether we have forcibly aborted the chain.
  bool _aborted = false;

  final Engine? _engine;
  final EngineRoute? _route;

  // Cache for query parameters
  Map<String, List<String>>? _queryCache;

  // Cache for form data
  Map<String, List<String>>? _formCache;

  /// Unique identifier for tracking, same as request.id.
  final String id;

  /// Retrieves the engine configuration.
  EngineConfig get engineConfig => _engine?.config ?? EngineConfig();

  /// Create a new context around a [Request] and [Response].
  EngineContext({
    required this.request,
    required Response response,
    List<Handler>? handlers,
    Engine? engine,
    EngineRoute? route,
  })  : _response = response,
        _engine = engine,
        _route = route,
        id = request.id {
    if (handlers != null && handlers.isNotEmpty) {
      _handlers = handlers;
    }
  }

  // Cache keys are constants
  final String queryCacheKey = "__queryCache";
  final String formCacheKey = "__formCache";
  final String multipartFormKey = '__multipartForm';

  /// Retrieves the form cache asynchronously.
  Future<Map<String, dynamic>> get formCache async {
    await initFormCache();
    return get(formCacheKey);
  }

  /// Retrieves the multipart form asynchronously.
  Future<MultipartForm> get multipartForm async {
    await initFormCache();
    return get(multipartFormKey) ?? MultipartForm();
  }

  /// Initializes the form cache by parsing form data.
  Future<Map<String, dynamic>> initFormCache() async {
    final cached = get<Map<String, dynamic>>(formCacheKey);
    if (cached != null) return cached;

    final form = <String, dynamic>{};

    // Handle URL-encoded forms
    if (request.contentType?.subType == 'x-www-form-urlencoded') {
      form.addAll(await parseForm(this));
    }

    // Handle multipart forms
    if (request.contentType?.subType == 'form-data') {
      final multipartForm = await parseMultipartForm(this);
      set(multipartFormKey, multipartForm);
      form.addAll(multipartForm.fields);
    }

    // Cache the combined results
    set(formCacheKey, form);
    return form;
  }

  /// Retrieves the query cache.
  Map<String, dynamic> get queryCache {
    final cache = get<Map<String, dynamic>>(queryCacheKey);
    if (cache != null) return cache;
    set(queryCacheKey, parseUrlEncoded(uri.query));
    return get(queryCacheKey)!;
  }

  /// Retrieve a stored value by [key].
  T? get<T>(String key) => request.getAttribute<T>(key);

  /// Retrieve a stored value by [key] and throw an error if not found.
  T mustGet<T>(String key) {
    final value = get<T>(key);
    if (value == null) {
      throw StateError('Key $key not found in context');
    }
    return value;
  }

  /// Store a value [value] under [key].
  void set(String key, dynamic value) {
    request.setAttribute(key, value);
  }

  /// Check if we have aborted the chain.
  bool get isAborted => _aborted;

  /// Abort the remaining handlers; no further `ctx.next()` calls will proceed.
  void abort() {
    _aborted = true;
  }

  /// Abort the chain immediately and write a specific [statusCode] plus [message].
  void abortWithStatus(int statusCode, [String message = '']) {
    _response.statusCode = statusCode;
    if (message.isNotEmpty) {
      _response.write(message);
    }
    abort();
  }

  /// Abort the chain immediately and write a specific [statusCode] plus [message].
  void abortWithError(int statusCode, [String message = '']) {
    abort();
    _response.statusCode = statusCode;
    if (message.isNotEmpty) {
      _response.write(message);
    }
  }

  /// Add an error to this context, optionally specifying a type or other metadata.
  EngineError addError(String message, {int? code}) {
    final err = EngineError(message: message, code: code);
    _errors.add(err);
    return err;
  }

  /// Retrieve all errors attached to this context.
  List<EngineError> get errors => List.unmodifiable(_errors);

  /// Check if the response is closed.
  bool get isClosed => _response.isClosed;

  /// Retrieve the request headers.
  HttpHeaders get headers => request.headers;

  /// Retrieve the request method.
  String get method => request.method;

  /// Retrieve the request URI.
  Uri get uri => request.uri;

  /// Retrieve the response object.
  Response get response => _response;

  /// Reset the chain index so we can re-run (uncommon).
  void resetHandlers() {
    _index = -1;
    _aborted = false;
    clear();
  }

  /// Move to the next handler in the chain, if available and not aborted.
  Future<void> next() async {
    if (_aborted || _handlers == null || _response.isClosed) {
      return;
    }
    _index++;
    if (_index < _handlers!.length) {
      await _handlers![_index](this);
    }
  }

  /// Helper to start processing the chain from the first handler.
  Future<void> run() async {
    resetHandlers();
    await next(); // start from index = -1 -> 0
  }

  /// Write a string to the response.
  void write(String s) {
    _response.write(s);
  }

  /// Set a cookie in the response.
  void setCookie(String name, value,
      {int maxAge = 0,
      String path = '/',
      String domain = '',
      bool secure = false,
      SameSite? sameSite,
      httpOnly = false}) {
    _response.setCookie(name, value,
        path: path,
        domain: domain,
        httpOnly: httpOnly,
        sameSite: sameSite,
        maxAge: maxAge,
        secure: secure);
  }

  /// Retrieve a cookie from the request.
  Cookie? cookie(String s) {
    return request.cookies.where((c) => c.name == s).firstOrNull;
  }

  /// Retrieve a parameter from the route.
  param(String s) {
    if (_route == null) {
      return null;
    }
    final params = _route.extractParameters(request.path);
    return params[s];
  }

  /// Retrieve a query parameter from the request.
  query(String s) {
    return queryCache[s];
  }

  /// Retrieve a header from the request.
  String? requestHeader(String s) {
    return request.headers[s]?.join(',');
  }

  /// Retrieve the content type of the request.
  String? contentType() {
    return request.contentType?.primaryType ?? '';
  }

  /// Filter flags from a content string.
  String filterFlags(String content) {
    for (int i = 0; i < content.length; i++) {
      var char = content[i];
      if (char == ' ' || char == ';') {
        return content.substring(0, i);
      }
    }
    return content;
  }

  /// Sets the HTTP status code for the response.
  void status(int code) {
    _response.statusCode = code;
  }

  /// Helper method to determine if a body is allowed for the given status code.
  bool _bodyAllowedForStatus(int statusCode) {
    return !(statusCode >= 100 && statusCode < 200 ||
        statusCode == 204 ||
        statusCode == 304);
  }

  /// Retrieve route parameters.
  Map<String, dynamic> get params =>
      _route?.extractParameters(request.path) ?? {};

  /// Set a header in the response.
  void setHeader(String s, String t) {
    _response.headers.add(s, t);
  }

  /// Store context-scoped data.
  void setContextData(String key, dynamic value) {
    request.setAttribute(key, value);
  }

  /// Retrieve context-scoped data.
  T? getContextData<T>(String key) {
    return request.getAttribute<T>(key);
  }

  /// Clear all data for this request context.
  void clear() {
    request.clearAttributes();
  }
}

extension MultipartFormMethods on EngineContext {
  /// Retrieve the multipart form asynchronously.
  Future<MultipartForm> multipartForm() async {
    await initFormCache();
    final a = get<MultipartForm>(multipartFormKey) ?? MultipartForm();
    return a;
  }

  /// Retrieve a file from the multipart form.
  Future<MultipartFile?> formFile(String name) async {
    final form = await multipartForm();
    return form.files.where((f) => f.name == name).firstOrNull;
  }

  /// Save an uploaded file to a destination.
  Future<void> saveUploadedFile(MultipartFile file, String destination) async {
    final sourceFile = _engine?.config.fileSystem.file(file.path);
    final destFile = _engine?.config.fileSystem.file(destination);
    await sourceFile?.copy(destFile?.path ?? "");
  }

  /// Get the first value of a form field with a default fallback.
  Future<String> defaultPostForm(String key, String defaultValue) async {
    final value = (await postForm(key));
    return value.isEmpty ? defaultValue : value;
  }

  /// Get the value of a form field.
  Future<String> postForm(String key) async {
    await initFormCache();
    final form = get<Map<String, dynamic>>(formCacheKey) ?? {};
    return form[key] ?? "";
  }

  /// Get all values of a form field.
  Future<List<String>> postFormArray(String key) async {
    final form = get<Map<String, dynamic>>(formCacheKey) ?? {};
    return form[key] ?? [];
  }

  /// Get a map of form fields with a key prefix.
  Future<Map<String, dynamic>> postFormMap(String key) async {
    await initFormCache();
    return get<Map<String, dynamic>>(formCacheKey) ?? {};
  }
}

extension QueryMethods on EngineContext {
  /// Retrieve a query parameter by key.
  T? getQuery<T>(String key) {
    final value = queryCache[key];
    if (value == null || value.isEmpty) return null;
    return value as T;
  }

  /// Retrieve an array of query parameters by key.
  List<String> getQueryArray(String key) {
    final values = getQuery<List<String>>(key);
    if (values == null) return [];
    return values;
  }

  /// Get a query parameter with a default fallback.
  T defaultQuery<T>(String key, T defaultValue) {
    final result = getQuery(key);
    if (!result.found) return defaultValue;
    return result.value as T;
  }

  /// Get all values for a query key.
  List<String> queryArray(String key) {
    return getQueryArray(key);
  }

  /// Get a map of query parameters with a key prefix.
  Map<String, String> queryMap(String keyPrefix) {
    return getQueryMap(keyPrefix).$1;
  }

  /// Get a map of query parameters with an existence flag.
  (Map<String, String>, bool) getQueryMap(String keyPrefix) {
    final result = <String, String>{};
    var found = false;

    for (final entry in request.uri.queryParametersAll.entries) {
      if (entry.key.startsWith(keyPrefix)) {
        found = true;
        if (entry.value.isNotEmpty) {
          result[entry.key] = entry.value.first;
        }
      }
    }

    return (result, found);
  }
}
