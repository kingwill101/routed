import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart' show internal;
import 'package:path/path.dart' as p;
import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/binding/convert/sse.dart';
import 'package:routed/src/binding/multipart.dart';
import 'package:routed/src/binding/utils.dart';
import 'package:routed/src/cache/cache.dart';
import 'package:routed/src/container/container.dart' show Container;
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/contracts/translation/translator.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/engine_template.dart';
import 'package:routed/src/file_handler.dart';
import 'package:routed/src/http/negotiation.dart';
import 'package:routed/src/render/data_render.dart';
import 'package:routed/src/render/html.dart';
import 'package:routed/src/render/json_render.dart';
import 'package:routed/src/render/reader_render.dart';
import 'package:routed/src/render/redirect.dart';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/render/string_render.dart';
import 'package:routed/src/render/xml.dart';
import 'package:routed/src/render/yaml.dart';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed/src/translation/constants.dart';
import 'package:routed/src/view/view_engine.dart';

import '../../middlewares.dart' show Middleware, disableCompression;

part 'binding.dart';
part 'cache.dart';
part 'error.dart';

part 'helpers.dart';

part 'multipart.dart';

part 'negotiation.dart';
part 'proxy.dart';

part 'query.dart';
part 'render.dart';
part 'session.dart';

part 'sse.dart';

part 'shortcuts.dart';

/// The EngineContext is loosely inspired by gin.Context in Go.
/// It wraps [Request] and [Response], holds arbitrary keys/values,
/// tracks errors, and can control flow in a chain of handlers.
class EngineContext {
  /// The current HTTP request data.
  @internal
  final Request request;

  /// The current HTTP response writer.
  final Response _response;

  /// Track errors that occur during request handling.
  /// Similar to gin.Context.Errors.
  final List<EngineError> _errors = [];

  /// Handlers/middlewares chain returning Response via Next.
  List<Middleware>? _handlers;

  /// Indicates the underlying connection has been upgraded and detached.
  bool _upgraded = false;

  /// Current index in the handler chain.
  int _index = -1;

  /// Indicates whether we have forcibly aborted the chain.
  bool _aborted = false;

  final Engine? _engine;

  final EngineRoute? _route;

  final Container? _container;

  /// Unique identifier for tracking, same as request.id.
  final String id;

  Engine? get engine => _engine;

  /// Retrieves the engine configuration.
  EngineConfig get engineConfig => _engine?.config ?? EngineConfig();

  /// Retrieves the request-scoped container.
  Container get container {
    final container = _container ?? _engine?.container;
    if (container == null) {
      throw StateError('No container associated with this context');
    }
    return container;
  }

  /// Create a new context around a [Request] and [Response].
  EngineContext({
    required this.request,
    required Response response,
    List<Middleware>? handlers,
    Engine? engine,
    EngineRoute? route,
    Container? container,
  }) : _response = response,
       _engine = engine,
       _route = route,
       _container = container,
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
    return get<Map<String, dynamic>>(formCacheKey) ?? <String, dynamic>{};
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

  /// Indicates that the connection has been upgraded and detached.
  bool get isUpgraded => _upgraded;

  /// Retrieve the request headers.
  HttpHeaders get headers => request.headers;

  /// Retrieve the request method.
  String get method => request.method;

  /// Retrieve the request URI.
  Uri get uri => request.uri;

  /// Retrieve the requested URI for the request.
  Uri get requestedUri => request.requestedUri;

  /// Retrieve the request host.
  String get host => request.host;

  /// Retrieve the request scheme.
  String get scheme => request.scheme;

  /// Retrieve the response object.
  @internal
  Response get response => _response;

  /// Close the response and await the underlying HttpResponse completion.
  Future<void> close() => _response.close();

  /// Reset the chain index so we can re-run (uncommon).
  void resetHandlers() {
    _index = -1;
    _aborted = false;
    clear();
  }

  /// Move to the next handler in the chain, if available and not aborted.
  Future<Response> _nextImpl() async {
    if (_aborted || _handlers == null || _response.isClosed) {
      return _response;
    }
    _index++;
    if (_index < _handlers!.length) {
      final current = _handlers![_index];
      FutureOr<Response> next() => _nextImpl();
      final result = await current(this, next);
      return result;
    }
    return _response;
  }

  /// Helper to start processing the chain from the first handler.
  Future<Response> run() async {
    resetHandlers();
    return await _nextImpl(); // start from index = -1 -> 0
  }

  /// Upgrades the HTTP connection and yields the underlying socket to the caller.
  ///
  /// This mirrors Shelf's `Request.hijack` pattern but ensures the Engine stays
  /// aware of the upgrade lifecycle. Only one upgrade is allowed per request.
  Future<T> upgrade<T>(
    Future<T> Function(Socket socket) handler, {
    bool writeHeaders = true,
  }) async {
    if (_upgraded) {
      throw StateError(
        'Connection has already been upgraded for this request.',
      );
    }
    if (_response.isClosed) {
      throw StateError('Response is already closed; cannot upgrade.');
    }
    if (request.protocolVersion != '1.1') {
      throw StateError(
        'Connection upgrades are only supported for HTTP/1.1 requests.',
      );
    }

    _upgraded = true;

    await _response.flush();
    final socket = await _response.detachSocket(writeHeaders: writeHeaders);

    try {
      return await handler(socket);
    } catch (error, stack) {
      try {
        await socket.close();
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Write a string to the response.
  void write(String s) {
    _response.write(s);
  }

  /// Set a cookie in the response.
  void setCookie(
    String name,
    String value, {
    int maxAge = 0,
    String path = '/',
    String domain = '',
    bool secure = false,
    SameSite? sameSite,
    bool httpOnly = false,
  }) {
    _response.setCookie(
      name,
      value,
      path: path,
      domain: domain,
      httpOnly: httpOnly,
      sameSite: sameSite,
      maxAge: maxAge,
      secure: secure,
    );
  }

  /// Retrieve a cookie from the request.
  Cookie? cookie(String s) {
    return request.cookies.where((c) => c.name == s).firstOrNull;
  }

  /// Retrieve a parameter from the route.
  String? param(String s) {
    final value = params[s];
    return value?.toString();
  }

  /// Retrieve a required route parameter as type [T].
  ///
  /// Throws a [StateError] when the parameter is missing. If the
  /// parameter exists but cannot be cast to `T`, the regular Dart
  /// `TypeError` / `CastError` will surface, keeping the behaviour
  /// identical to prior releases.
  T mustGetParam<T>(String s) {
    final map = params;
    if (!map.containsKey(s) || map[s] == null) {
      throw StateError('Missing required param $s');
    }
    return map[s] as T;
  }

  /// Retrieve a query parameter from the request.
  dynamic query(String s) {
    return queryCache[s];
  }

  /// Retrieve a header from the request.
  String? requestHeader(String s) {
    final target = s.toLowerCase();
    String? result;
    request.headers.forEach((k, v) {
      if (k.toLowerCase() == target) {
        result = v.join(',');
      }
    });
    return result;
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
  Map<String, dynamic> get params {
    if (_route != null) {
      final extracted = _route.extractParameters(request.path);
      if (request.pathParameters.isEmpty) {
        return extracted;
      }
      return {...request.pathParameters, ...extracted};
    }
    if (request.pathParameters.isEmpty) {
      return const {};
    }
    return Map<String, dynamic>.from(request.pathParameters);
  }

  /// Set a header in the response.
  void setHeader(String s, String t) {
    _response.headers.add(s, t);
  }

  String? header(String s) {
    final value = _response.headers[s]?.join(', ');
    if (value == null) {
      return null;
    }
    return value;
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
