@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart';
import 'package:web/web.dart' as web;

import '../runtime/host_context.dart';
import '../runtime/runtime.dart';
import '../fetch/web_stream_bridge.dart';
import 'cloudflare_types.dart';

@JS('Response')
external JSFunction? get _responseConstructor;

@JS('Reflect.apply')
external JSAny? _reflectApply(
  JSAny target,
  JSAny? thisArgument,
  JSArray argumentsList,
);

@JS('WebSocketPair')
extension type _NativeCloudflareWebSocketPair._(JSObject _)
    implements JSObject {
  external factory _NativeCloudflareWebSocketPair();

  @JS('0')
  external JSObject get client;

  @JS('1')
  external JSObject get server;
}

JSAny? _property(JSObject object, String name) => object.getProperty(name.toJS);

JSObject _object(Object value) {
  if (value is JSObject) return value;
  throw ArgumentError.value(value, 'value', 'Expected a JavaScript object.');
}

Object? _dartify(JSAny? value) => value.dartify();

JSAny? _jsify(Object? value) => value.jsify();

JSAny? _call(JSObject object, String method, Iterable<JSAny?> arguments) {
  final function = _property(object, method);
  if (function == null || !function.isA<JSFunction>()) {
    throw StateError('Cloudflare binding does not implement $method().');
  }
  return object.callMethodVarArgs<JSAny?>(method.toJS, arguments.toList());
}

JSAny? _callRpcMethod(
  JSObject object,
  String method,
  Iterable<JSAny?> arguments,
) {
  final function = _property(object, method);
  if (function == null) {
    throw StateError('Cloudflare RPC method not found: $method.');
  }
  // Reflect.apply preserves the service-binding proxy as the receiver and
  // accepts both ordinary functions in tests and Cloudflare RPC callables.
  return _reflectApply(
    function,
    object,
    arguments.toList().jsify()! as JSArray,
  );
}

Future<JSAny?> _promise(JSAny? value) async {
  if (value == null) return null;
  if (value.isA<JSPromise<JSAny?>>()) {
    return (value as JSPromise<JSAny?>).toDart;
  }
  if (!value.isA<JSObject>()) return value;

  final object = value as JSObject;
  if (_property(object, 'then') == null) return value;

  // Cloudflare RPC returns a promise-like thenable rather than a native
  // Promise. Calling `then` directly keeps the bridge compatible with that
  // proxy while still accepting ordinary synchronous test doubles.
  final completer = Completer<JSAny?>();
  final onValue = ((JSAny? result) {
    if (!completer.isCompleted) completer.complete(result);
  }).toJS;
  final onError = ((JSAny? error) {
    if (!completer.isCompleted) {
      completer.completeError(
        error ?? StateError('JavaScript promise failed.'),
      );
    }
  }).toJS;
  try {
    object.callMethodVarArgs<JSAny?>('then'.toJS, [onValue, onError]);
  } catch (error, stackTrace) {
    if (!completer.isCompleted) completer.completeError(error, stackTrace);
  }
  return completer.future;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

num? _num(Object? value) => value is num ? value : null;

String? _string(Object? value) => value is String ? value : null;

Map<String, String> _headers(JSObject object) {
  final headers = _property(object, 'headers');
  if (headers == null || !headers.isA<JSObject>()) return const {};
  final headersObject = headers as JSObject;
  final entries = _property(headersObject, 'entries');
  if (entries == null || !entries.isA<JSFunction>()) return const {};
  final iterator = (entries as JSFunction).callAsFunction(headersObject);
  if (iterator == null || !iterator.isA<JSObject>()) return const {};
  final next = _property(iterator as JSObject, 'next');
  if (next == null || !next.isA<JSFunction>()) return const {};

  final result = <String, String>{};
  final iteratorObject = iterator;
  while (true) {
    final item = (next as JSFunction).callAsFunction(iteratorObject);
    if (item == null || !item.isA<JSObject>()) break;
    final itemObject = item as JSObject;
    final done = _property(itemObject, 'done');
    if (done != null && done.isA<JSBoolean>() && (done as JSBoolean).toDart) {
      break;
    }
    final value = _property(itemObject, 'value');
    if (value == null || !value.isA<JSArray>()) break;
    final pair = value as JSArray;
    if (pair.length < 2) break;
    final name = pair.getProperty(0.toJS);
    final headerValue = pair.getProperty(1.toJS);
    if (name != null &&
        headerValue != null &&
        name.isA<JSString>() &&
        headerValue.isA<JSString>()) {
      result[(name as JSString).toDart] = (headerValue as JSString).toDart;
    }
  }
  return result;
}

JSAny? _cloudflareFetchBody(Object? body) {
  if (body == null) return null;
  if (body is String) return body.toJS;
  if (body is Uint8List) return body.toJS;
  throw ArgumentError.value(
    body,
    'body',
    'Cloudflare request and response bodies support String and Uint8List.',
  );
}

JSAny _nativeWebSocket(CloudflareWebSocket webSocket) {
  if (webSocket is! _CloudflareWebSocket) {
    throw ArgumentError.value(
      webSocket,
      'webSocket',
      'The WebSocket must come from this Cloudflare Worker runtime.',
    );
  }
  return webSocket._delegate;
}

web.Response _nativeResponse(CloudflareResponse response) {
  final webSocket = response.webSocket;
  if (webSocket != null) {
    final constructor = _responseConstructor;
    if (constructor == null) {
      throw UnsupportedError('WebSocket upgrades require native Response.');
    }
    final init = web.ResponseInit(
      status: response.status,
      statusText: 'Switching Protocols',
      headers: _jsify(response.headers) as JSObject,
    )..setProperty('webSocket'.toJS, _nativeWebSocket(webSocket));
    return constructor.callAsConstructorVarArgs<web.Response>([null, init]);
  }
  return web.Response(
    _cloudflareFetchBody(response.body),
    web.ResponseInit(
      status: response.status,
      headers: _jsify(response.headers) as JSObject,
    ),
  );
}

Future<CloudflareResponse> _cloudflareResponseFromJavaScript(
  JSAny response,
) async {
  final native = response as web.Response;
  final webSocket = _property(native, 'webSocket');
  if (webSocket is JSObject) {
    return CloudflareResponse.webSocket(
      _CloudflareWebSocket(webSocket),
      headers: _headers(native),
    );
  }
  final body = (await native.arrayBuffer().toDart).toDart.asUint8List();
  return CloudflareResponse.bytes(
    body,
    status: native.status,
    headers: _headers(native),
  );
}

Future<CloudflareResponse?> _nullableCloudflareResponseFromJavaScript(
  JSAny? response,
) async {
  if (response == null) return null;
  return _cloudflareResponseFromJavaScript(response);
}

final class _CloudflareRequest implements CloudflareRequest {
  _CloudflareRequest(this._delegate);

  final web.Request _delegate;

  @override
  String get method => _delegate.method;

  @override
  String get url => _delegate.url;

  @override
  Map<String, String> get headers => _headers(_delegate);

  @override
  Map<String, Object?> get cf => _map(_dartify(_property(_delegate, 'cf')));

  @override
  Future<String> text() async => (await _delegate.text().toDart).toDart;

  @override
  Future<T?> json<T>({CloudflareJsonDecoder<T>? decode}) async {
    final value = _dartify(await _delegate.json().toDart);
    return decode == null ? value as T? : decode(value);
  }
}

final class _CloudflareWebSocket implements CloudflareWebSocket {
  _CloudflareWebSocket(this._delegate);

  final JSObject _delegate;

  @override
  int get readyState => _int(_dartify(_property(_delegate, 'readyState'))) ?? 0;

  @override
  void send(Object data) {
    _call(_delegate, 'send', <JSAny?>[_cloudflareFetchBody(data)]);
  }

  @override
  void close([int? code, String? reason]) {
    _call(_delegate, 'close', <JSAny?>[
      if (code != null) code.toJS,
      if (reason != null) reason.toJS,
    ]);
  }

  @override
  void serializeAttachment(Object? attachment) {
    _call(_delegate, 'serializeAttachment', <JSAny?>[_jsify(attachment)]);
  }

  @override
  T? deserializeAttachment<T>({CloudflareJsonDecoder<T>? decode}) {
    final rawValue = _dartify(
      _call(_delegate, 'deserializeAttachment', const <JSAny?>[]),
    );
    final value = rawValue is Map ? _map(rawValue) : rawValue;
    return decode == null ? value as T? : decode(value);
  }
}

final class _CloudflareWebSocketPair implements CloudflareWebSocketPair {
  _CloudflareWebSocketPair(_NativeCloudflareWebSocketPair pair)
    : client = _CloudflareWebSocket(pair.client),
      server = _CloudflareWebSocket(pair.server);

  @override
  final CloudflareWebSocket client;

  @override
  final CloudflareWebSocket server;

  @override
  CloudflareResponse get response => CloudflareResponse.webSocket(client);
}

/// Creates the native Cloudflare `WebSocketPair` without exposing its
/// JavaScript representation to application code.
CloudflareWebSocketPair cloudflareWebSocketPair() =>
    _CloudflareWebSocketPair(_NativeCloudflareWebSocketPair());

Object _cloudflareWebSocketMessage(JSAny? value) {
  if (value is JSString) return value.toDart;
  if (value is JSArrayBuffer) return value.toDart.asUint8List();
  final dartValue = _dartify(value);
  if (dartValue is String) return dartValue;
  if (dartValue is Uint8List) return dartValue;
  throw StateError(
    'Cloudflare WebSocket messages must be text or binary data.',
  );
}

JSObject _nativeRequest(CloudflareRequest request) {
  if (request is! _CloudflareRequest) {
    throw ArgumentError.value(
      request,
      'request',
      'The request must come from a Cloudflare Worker context.',
    );
  }
  return request._delegate;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, Object?>{};
}

List<Object?> _list(Object? value) {
  if (value is Iterable) return value.toList();
  if (value is JSArray) {
    return value.toDart.map(_dartify).toList();
  }
  return <Object?>[];
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, String> _stringMap(Object? value) =>
    _map(value).map((key, value) => MapEntry(key, value.toString()));

JSAny? _r2Body(Object? value) {
  if (value == null) return null;
  if (value is String) return value.toJS;
  if (value is Uint8List) return value.toJS;
  if (value is List<int>) return Uint8List.fromList(value).toJS;
  if (value is Stream<List<int>>) return webStreamFromDart(value);
  throw ArgumentError.value(
    value,
    'value',
    'R2 values must be String, bytes, or Stream<List<int>>.',
  );
}

CloudflareR2Object? _r2Object(JSAny? value, {bool includeBody = true}) {
  if (value == null || !value.isA<JSObject>()) return null;
  final object = value as JSObject;
  final bodyValue = _property(object, 'body');
  final body = includeBody && bodyValue is JSObject
      ? dartStreamFromWeb(bodyValue as web.ReadableStream)
      : null;
  return CloudflareR2Object(
    key: _string(_dartify(_property(object, 'key'))) ?? '',
    version: _string(_dartify(_property(object, 'version'))),
    size: _int(_dartify(_property(object, 'size'))),
    etag: _string(_dartify(_property(object, 'etag'))),
    httpEtag: _string(_dartify(_property(object, 'httpEtag'))),
    uploaded: _dateTime(_dartify(_property(object, 'uploaded'))),
    httpMetadata: _stringMap(_dartify(_property(object, 'httpMetadata'))),
    customMetadata: _stringMap(_dartify(_property(object, 'customMetadata'))),
    checksums: _stringMap(_dartify(_property(object, 'checksums'))),
    body: body,
  );
}

String _queueContentTypeName(CloudflareQueueContentType value) =>
    switch (value) {
      CloudflareQueueContentType.text => 'text',
      CloudflareQueueContentType.bytes => 'bytes',
      CloudflareQueueContentType.json => 'json',
      CloudflareQueueContentType.v8 => 'v8',
    };

CloudflareQueueMetrics _queueMetrics(Object? value) {
  final metrics = _map(value);
  return CloudflareQueueMetrics(
    backlogCount: _int(metrics['backlogCount'] ?? metrics['backlog_count']),
    backlogBytes: _int(metrics['backlogBytes'] ?? metrics['backlog_bytes']),
    oldestMessageTimestamp: _dateTime(
      metrics['oldestMessageTimestamp'] ?? metrics['oldest_message_timestamp'],
    ),
  );
}

CloudflareQueueSendResult _queueSendResult(Object? value) {
  final result = _map(value);
  final metadata = _map(result['metadata']);
  final metrics = metadata['metrics'];
  return CloudflareQueueSendResult(
    metrics: metrics == null ? null : _queueMetrics(metrics),
  );
}

CloudflareWorkflowError? _workflowError(Object? value) {
  if (value == null) return null;
  final error = _map(value);
  final name = _string(error['name']);
  final message = _string(error['message']);
  if (name == null || message == null) return null;
  return CloudflareWorkflowError(name: name, message: message);
}

CloudflareWorkflowStatus _workflowStatus(Object? value) {
  final status = _map(value);
  return CloudflareWorkflowStatus(
    status: _string(status['status']) ?? 'unknown',
    error: _workflowError(status['error']),
    output: status['output'],
    rollback: _workflowRollback(status['rollback']),
  );
}

CloudflareWorkflowRollback? _workflowRollback(Object? value) {
  if (value == null) return null;
  final rollback = _map(value);
  final outcome = _string(rollback['outcome']);
  if (outcome == null) return null;
  return CloudflareWorkflowRollback(
    outcome: outcome,
    error: _workflowError(rollback['error']),
  );
}

String _containerStreamMode(CloudflareContainerStreamMode mode) =>
    switch (mode) {
      CloudflareContainerStreamMode.pipe => 'pipe',
      CloudflareContainerStreamMode.ignore => 'ignore',
      CloudflareContainerStreamMode.combined => 'combined',
    };

JSAny? _containerStartOptions(CloudflareContainerStartOptions options) =>
    _jsify({
      if (options.environment.isNotEmpty) 'env': options.environment,
      if (options.entrypoint.isNotEmpty) 'entrypoint': options.entrypoint,
      if (options.enableInternet != null)
        'enableInternet': options.enableInternet,
    });

JSAny? _containerExecOptions(CloudflareContainerExecOptions options) {
  if (options.stdout == CloudflareContainerStreamMode.combined) {
    throw ArgumentError.value(
      options.stdout,
      'stdout',
      'Cloudflare Container stdout does not support combined output.',
    );
  }
  if (options.stderr == CloudflareContainerStreamMode.combined &&
      options.stdout == CloudflareContainerStreamMode.ignore) {
    throw ArgumentError(
      'Cloudflare Container combined stderr requires stdout to be piped.',
    );
  }
  return _jsify({
    'stdout': _containerStreamMode(options.stdout),
    'stderr': _containerStreamMode(options.stderr),
    if (options.environment.isNotEmpty) 'env': options.environment,
    if (options.cwd != null) 'cwd': options.cwd,
    if (options.user != null) 'user': options.user,
  });
}

Uint8List _containerBytes(Object? value) {
  if (value is JSArrayBuffer) return value.toDart.asUint8List();
  if (value is JSUint8Array) return value.toDart;
  final dartValue = value is JSAny ? _dartify(value) : value;
  return dartValue is Uint8List ? dartValue : Uint8List(0);
}

CloudflareD1Meta? _meta(Object? value) {
  if (value == null) return null;
  final meta = _map(value);
  return CloudflareD1Meta(
    duration: _num(meta['duration']),
    rowsRead: _int(meta['rowsRead'] ?? meta['rows_read']),
    rowsWritten: _int(meta['rowsWritten'] ?? meta['rows_written']),
    changes: _int(meta['changes']),
    changedDb: meta['changed_db'] as bool? ?? meta['changedDb'] as bool?,
    sizeAfter: _int(meta['size_after'] ?? meta['sizeAfter']),
    lastRowId: meta['last_row_id'] ?? meta['lastRowId'],
    servedBy: _string(meta['served_by'] ?? meta['servedBy']),
    servedByColo: _string(meta['served_by_colo'] ?? meta['servedByColo']),
    servedByPrimary:
        (meta['served_by_primary'] ?? meta['servedByPrimary']) as bool?,
    servedByRegion: _string(meta['served_by_region'] ?? meta['servedByRegion']),
    servedByLocation: _string(
      meta['served_by_location'] ?? meta['servedByLocation'],
    ),
    bookmark: _string(meta['bookmark']),
  );
}

CloudflareD1Result<T> _d1Result<T>(
  Object? value, {
  CloudflareD1RowDecoder<T>? decode,
}) {
  final result = _map(value);
  final rows = _list(result['results']).map(_map).map((row) {
    if (decode != null) return decode(row);
    return row as T;
  }).toList();
  return CloudflareD1Result<T>(
    success: result['success'] == true,
    results: rows,
    meta: _meta(result['meta']),
    error: result['error'],
  );
}

/// Returns the Worker environment associated with [context], when present.
CloudflareEnvironment? cloudflareEnvironmentOf(EngineContext context) {
  final extension = routedNodeExtensionOf<FetchRuntimeExtension>(context);
  final environment = extension?.environment;
  if (environment is CloudflareEnvironment) return environment;
  return environment == null
      ? null
      : cloudflareEnvironmentFromJavaScript(environment);
}

/// Reads a text or secret Worker binding without exposing JavaScript interop.
String cloudflareTextBinding(CloudflareEnvironment environment, String name) {
  final value = environment.binding(name);
  if (value is String) return value;
  if (value is JSString) return value.toDart;
  throw StateError('Cloudflare binding is not text: $name.');
}

/// Returns the native Fetch request associated with [context], when present.
CloudflareRequest? cloudflareRequestOf(EngineContext context) {
  final extension = routedNodeExtensionOf<FetchRuntimeExtension>(context);
  final request = extension?.request;
  return request == null ? null : _CloudflareRequest(request as web.Request);
}

/// Performs the createCloudflareRequest operation.
CloudflareRequest createCloudflareRequest(
  String url, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  Object? body,
}) => _CloudflareRequest(
  web.Request(
    url.toJS,
    web.RequestInit(
      method: method,
      headers: _jsify(headers) as JSObject,
      body: _cloudflareFetchBody(body),
    ),
  ),
);

/// Returns the default Cloudflare Cache API namespace or a named cache.
Future<CloudflareCache> cloudflareCache({String? name}) async {
  final caches = _property(globalContext, 'caches');
  if (caches == null || !caches.isA<JSObject>()) {
    throw UnsupportedError('Cloudflare Cache API is unavailable.');
  }
  final storage = caches as JSObject;
  if (name == null) {
    final cache = _property(storage, 'default');
    if (cache == null || !cache.isA<JSObject>()) {
      throw StateError('Cloudflare default cache is unavailable.');
    }
    return _CloudflareCache(cache as JSObject);
  }
  final cache = await _promise(_call(storage, 'open', <JSAny?>[name.toJS]));
  if (cache == null || !cache.isA<JSObject>()) {
    throw StateError('Cloudflare cache "$name" was not opened.');
  }
  return _CloudflareCache(cache as JSObject);
}

/// Wraps a native Worker environment.
CloudflareEnvironment cloudflareEnvironmentFromJavaScript(Object environment) =>
    _CloudflareEnvironment(_object(environment));

/// Returns the Worker execution context associated with [context], when present.
CloudflareExecutionContext? cloudflareExecutionContextOf(
  EngineContext context,
) {
  final extension = routedNodeExtensionOf<FetchRuntimeExtension>(context);
  final executionContext = extension?.executionContext;
  return executionContext == null
      ? null
      : cloudflareExecutionContextFromJavaScript(executionContext);
}

/// Wraps a native Worker execution context.
CloudflareExecutionContext cloudflareExecutionContextFromJavaScript(
  Object executionContext,
) => _CloudflareExecutionContext(_object(executionContext));

final class _CloudflareEnvironment implements CloudflareEnvironment {
  _CloudflareEnvironment(this._delegate);

  final JSObject _delegate;

  @override
  Object binding(String name) {
    final binding = _property(_delegate, name);
    if (binding == null) {
      throw StateError('Cloudflare binding not found: $name.');
    }
    return binding;
  }

  @override
  CloudflareKvNamespace kv(String name) =>
      _CloudflareKvNamespace(_object(binding(name)));

  @override
  CloudflareD1Database d1(String name) =>
      _CloudflareD1Database(_object(binding(name)));

  @override
  CloudflareDurableObjectNamespace durableObjectNamespace(String name) =>
      _CloudflareDurableObjectNamespace(_object(binding(name)));

  @override
  CloudflareContainerBinding container(String name) =>
      _CloudflareContainerBinding(_object(binding(name)));

  @override
  CloudflareR2Bucket r2(String name) =>
      _CloudflareR2Bucket(_object(binding(name)));

  @override
  CloudflareQueue queue(String name) =>
      _CloudflareQueue(_object(binding(name)));

  @override
  CloudflareServiceBinding service(String name) =>
      _CloudflareServiceBinding(_object(binding(name)));

  @override
  CloudflareWorkerBinding worker(String name) =>
      _CloudflareServiceBinding(_object(binding(name)));

  @override
  CloudflareSecretsStoreBinding secretsStore(String name) =>
      _CloudflareSecretsStoreBinding(_object(binding(name)));

  @override
  CloudflareWorkflow workflow(String name) =>
      _CloudflareWorkflow(_object(binding(name)));
}

final class _CloudflareExecutionContext implements CloudflareExecutionContext {
  _CloudflareExecutionContext(this._delegate);

  final JSObject _delegate;

  @override
  void passThroughOnException() {
    _call(_delegate, 'passThroughOnException', const <JSAny?>[]);
  }

  @override
  void waitUntil(Future<void> future) {
    _call(_delegate, 'waitUntil', <JSAny?>[future.toJS]);
  }
}

final class _CloudflareCache implements CloudflareCache {
  _CloudflareCache(this._delegate);

  final JSObject _delegate;

  JSAny? _options(bool ignoreMethod) =>
      ignoreMethod ? _jsify(<String, Object?>{'ignoreMethod': true}) : null;

  @override
  Future<CloudflareResponse?> match(
    CloudflareRequest request, {
    bool ignoreMethod = false,
  }) async {
    final options = _options(ignoreMethod);
    return _nullableCloudflareResponseFromJavaScript(
      await _promise(
        _call(_delegate, 'match', <JSAny?>[_nativeRequest(request), ?options]),
      ),
    );
  }

  @override
  Future<void> put(
    CloudflareRequest request,
    CloudflareResponse response,
  ) async {
    await _promise(
      _call(_delegate, 'put', <JSAny?>[
        _nativeRequest(request),
        _nativeResponse(response),
      ]),
    );
  }

  @override
  Future<bool> delete(
    CloudflareRequest request, {
    bool ignoreMethod = false,
  }) async {
    final options = _options(ignoreMethod);
    return _dartify(
          await _promise(
            _call(_delegate, 'delete', <JSAny?>[
              _nativeRequest(request),
              ?options,
            ]),
          ),
        ) ==
        true;
  }
}

final class _CloudflareKvNamespace implements CloudflareKvNamespace {
  _CloudflareKvNamespace(this._delegate);

  final JSObject _delegate;

  Future<JSAny?> _get(String key, String type, int? cacheTtl) {
    final options = <String, Object?>{'type': type};
    if (cacheTtl != null) options['cacheTtl'] = cacheTtl;
    return _promise(
      _call(_delegate, 'get', <JSAny?>[key.toJS, _jsify(options)]),
    );
  }

  @override
  Future<String?> get(String key, {int? cacheTtl}) async =>
      _string(_dartify(await _get(key, 'text', cacheTtl)));

  @override
  Future<T?> getJson<T>(String key, {int? cacheTtl}) async {
    final value = _dartify(await _get(key, 'json', cacheTtl));
    return (value is Map ? _map(value) : value) as T?;
  }

  @override
  Future<Uint8List?> getBytes(String key, {int? cacheTtl}) async {
    final value = await _get(key, 'arrayBuffer', cacheTtl);
    if (value == null) return null;
    if (value is JSArrayBuffer) return value.toDart.asUint8List();
    final dartValue = _dartify(value);
    return dartValue is Uint8List ? dartValue : null;
  }

  @override
  Future<void> put(
    String key,
    Object value, {
    DateTime? expiration,
    int? expirationTtl,
    Object? metadata,
  }) {
    final options = <String, Object?>{};
    if (expiration != null) {
      options['expiration'] = expiration.millisecondsSinceEpoch ~/ 1000;
    }
    if (expirationTtl != null) options['expirationTtl'] = expirationTtl;
    if (metadata != null) options['metadata'] = metadata;
    return _promise(
      _call(_delegate, 'put', <JSAny?>[
        key.toJS,
        _jsify(value),
        _jsify(options),
      ]),
    );
  }

  @override
  Future<void> delete(Iterable<String> keys) async {
    final values = keys.toList();
    await _promise(_call(_delegate, 'delete', <JSAny?>[_jsify(values)]));
  }
}

final class _CloudflareD1Database implements CloudflareD1Database {
  _CloudflareD1Database(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareD1PreparedStatement prepare(String query) =>
      _CloudflareD1PreparedStatement(
        _object(_call(_delegate, 'prepare', <JSAny?>[query.toJS])!),
      );

  @override
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final delegates = statements.map((statement) {
      if (statement is! _CloudflareD1PreparedStatement) {
        throw ArgumentError.value(
          statement,
          'statements',
          'Statements must come from this D1 database binding.',
        );
      }
      return statement._delegate;
    }).toList();
    final value = _dartify(
      await _promise(_call(_delegate, 'batch', <JSAny?>[_jsify(delegates)])),
    );
    return _list(
      value,
    ).map((item) => _d1Result<T>(item, decode: decode)).toList();
  }

  @override
  Future<CloudflareD1ExecResult> exec(String query) async {
    final value = _map(
      _dartify(await _promise(_call(_delegate, 'exec', <JSAny?>[query.toJS]))),
    );
    return CloudflareD1ExecResult(
      count: _int(value['count']) ?? 0,
      duration: _num(value['duration']) ?? 0,
    );
  }

  @override
  Future<Uint8List> dump() async {
    final value = await _promise(_call(_delegate, 'dump', const <JSAny?>[]));
    if (value is JSArrayBuffer) return value.toDart.asUint8List();
    throw StateError('D1 dump() did not return an ArrayBuffer.');
  }

  @override
  CloudflareD1DatabaseSession withSession({String? bookmark}) {
    return _CloudflareD1DatabaseSession(
      _object(
        _call(_delegate, 'withSession', <JSAny?>[
          if (bookmark != null) bookmark.toJS,
        ])!,
      ),
    );
  }
}

final class _CloudflareD1DatabaseSession
    implements CloudflareD1DatabaseSession {
  _CloudflareD1DatabaseSession(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareD1PreparedStatement prepare(String query) =>
      _CloudflareD1PreparedStatement(
        _object(_call(_delegate, 'prepare', <JSAny?>[query.toJS])!),
      );

  @override
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final delegates = statements.map((statement) {
      if (statement is! _CloudflareD1PreparedStatement) {
        throw ArgumentError.value(
          statement,
          'statements',
          'Statements must come from this D1 session.',
        );
      }
      return statement._delegate;
    }).toList();
    final value = _dartify(
      await _promise(_call(_delegate, 'batch', <JSAny?>[_jsify(delegates)])),
    );
    return _list(
      value,
    ).map((item) => _d1Result<T>(item, decode: decode)).toList();
  }

  @override
  Future<String?> getBookmark() async => _string(
    _dartify(await _promise(_call(_delegate, 'getBookmark', const <JSAny?>[]))),
  );
}

final class _CloudflareD1PreparedStatement
    implements CloudflareD1PreparedStatement {
  _CloudflareD1PreparedStatement(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareD1PreparedStatement bind([Iterable<Object?> values = const []]) {
    final bound = _call(_delegate, 'bind', <JSAny?>[
      for (final value in values) _jsify(value),
    ]);
    return _CloudflareD1PreparedStatement(_object(bound!));
  }

  @override
  Future<CloudflareD1Result<T>> all<T>({
    CloudflareD1RowDecoder<T>? decode,
  }) async => _d1Result<T>(
    _dartify(await _promise(_call(_delegate, 'all', const <JSAny?>[]))),
    decode: decode,
  );

  @override
  Future<T?> first<T>({
    String? column,
    CloudflareD1RowDecoder<T>? decode,
  }) async {
    final value = _dartify(
      await _promise(
        _call(_delegate, 'first', <JSAny?>[if (column != null) column.toJS]),
      ),
    );
    if (value == null) return null;
    if (decode != null) return decode(_map(value));
    return (value is Map ? _map(value) : value) as T;
  }

  @override
  Future<CloudflareD1Result<T>> run<T>({
    CloudflareD1RowDecoder<T>? decode,
  }) async => _d1Result<T>(
    _dartify(await _promise(_call(_delegate, 'run', const <JSAny?>[]))),
    decode: decode,
  );

  @override
  Future<List<T>> raw<T>({CloudflareD1RowDecoder<T>? decode}) async {
    final rows = _list(
      _dartify(await _promise(_call(_delegate, 'raw', const <JSAny?>[]))),
    );
    return rows.map((row) {
      if (decode != null) return decode(_map(row));
      return (row is Map ? _map(row) : row) as T;
    }).toList();
  }
}

final class _CloudflareR2Bucket implements CloudflareR2Bucket {
  _CloudflareR2Bucket(this._delegate);

  final JSObject _delegate;

  @override
  Future<CloudflareR2Object?> head(String key) async => _r2Object(
    await _promise(_call(_delegate, 'head', <JSAny?>[key.toJS])),
    includeBody: false,
  );

  @override
  Future<CloudflareR2Object?> get(String key) async =>
      _r2Object(await _promise(_call(_delegate, 'get', <JSAny?>[key.toJS])));

  @override
  Future<CloudflareR2Object?> put(
    String key,
    Object? value, {
    CloudflareR2PutOptions? options,
  }) async {
    final putOptions = options;
    final optionsValue = putOptions == null
        ? null
        : <String, Object?>{
            if (putOptions.httpMetadata.isNotEmpty)
              'httpMetadata': putOptions.httpMetadata,
            if (putOptions.customMetadata.isNotEmpty)
              'customMetadata': putOptions.customMetadata,
          };
    return _r2Object(
      await _promise(
        _call(_delegate, 'put', <JSAny?>[
          key.toJS,
          _r2Body(value),
          if (optionsValue != null) _jsify(optionsValue),
        ]),
      ),
      includeBody: false,
    );
  }

  @override
  Future<void> delete(Object keys) async {
    final value = switch (keys) {
      String key => key.toJS,
      Iterable<String> values => _jsify(values.toList()),
      _ => throw ArgumentError.value(
        keys,
        'keys',
        'R2 delete keys must be a String or Iterable<String>.',
      ),
    };
    await _promise(_call(_delegate, 'delete', <JSAny?>[value]));
  }

  @override
  Future<CloudflareR2ListResult> list({
    CloudflareR2ListOptions? options,
  }) async {
    final value = await _promise(
      _call(_delegate, 'list', <JSAny?>[
        if (options != null)
          _jsify({
            if (options.limit != null) 'limit': options.limit,
            if (options.prefix != null) 'prefix': options.prefix,
            if (options.cursor != null) 'cursor': options.cursor,
            if (options.delimiter != null) 'delimiter': options.delimiter,
            if (options.include != null) 'include': options.include,
          }),
      ]),
    );
    final result = _object(value!);
    final objects = _list(_dartify(_property(result, 'objects')))
        .map((item) {
          final candidate = item is JSObject ? item : _jsify(item);
          return _r2Object(candidate, includeBody: false);
        })
        .whereType<CloudflareR2Object>()
        .toList();
    return CloudflareR2ListResult(
      objects: objects,
      truncated: _dartify(_property(result, 'truncated')) == true,
      cursor: _string(_dartify(_property(result, 'cursor'))),
      delimitedPrefixes: _list(
        _dartify(_property(result, 'delimitedPrefixes')),
      ).whereType<String>().toList(),
    );
  }
}

final class _CloudflareQueue implements CloudflareQueue {
  _CloudflareQueue(this._delegate);

  final JSObject _delegate;

  JSAny? _options({
    CloudflareQueueContentType? contentType,
    int? delaySeconds,
  }) {
    final value = <String, Object?>{
      if (contentType != null)
        'contentType': _queueContentTypeName(contentType),
      'delaySeconds': ?delaySeconds,
    };
    return value.isEmpty ? null : _jsify(value);
  }

  JSObject _message(CloudflareQueueMessage message) => _object(
    _jsify({
      'body': message.body,
      if (message.contentType != null)
        'contentType': _queueContentTypeName(message.contentType!),
      if (message.delaySeconds != null) 'delaySeconds': message.delaySeconds,
    })!,
  );

  @override
  Future<CloudflareQueueSendResult> send(
    Object? body, {
    CloudflareQueueContentType? contentType,
    int? delaySeconds,
  }) async {
    final value = await _promise(
      _call(_delegate, 'send', <JSAny?>[
        _jsify(body),
        _options(contentType: contentType, delaySeconds: delaySeconds),
      ]),
    );
    return _queueSendResult(_dartify(value));
  }

  @override
  Future<CloudflareQueueSendResult> sendBatch(
    Iterable<CloudflareQueueMessage> messages, {
    int? delaySeconds,
  }) async {
    final value = await _promise(
      _call(_delegate, 'sendBatch', <JSAny?>[
        messages.map(_message).toList().jsify(),
        _options(delaySeconds: delaySeconds),
      ]),
    );
    return _queueSendResult(_dartify(value));
  }

  @override
  Future<CloudflareQueueMetrics> metrics() async {
    final value = await _promise(_call(_delegate, 'metrics', const []));
    return _queueMetrics(_dartify(value));
  }
}

final class _CloudflareServiceBinding implements CloudflareServiceBinding {
  _CloudflareServiceBinding(this._delegate);

  final JSObject _delegate;

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    final response = await _promise(
      _call(_delegate, 'fetch', <JSAny?>[_nativeRequest(request)]),
    );
    if (response == null) {
      throw StateError('Cloudflare service binding fetch() returned null.');
    }
    return _cloudflareResponseFromJavaScript(response);
  }

  @override
  Future<T?> call<T>(
    String method, [
    Iterable<Object?> arguments = const [],
    CloudflareJsonDecoder<T>? decode,
  ]) async {
    final value = _callRpcMethod(_delegate, method, arguments.map(_jsify));
    final resolved = await _promise(value);
    final dartValue = _dartify(resolved);
    return decode == null ? dartValue as T? : decode(dartValue);
  }
}

final class _CloudflareContainerBinding implements CloudflareContainerBinding {
  _CloudflareContainerBinding(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareContainerInstance get(String sessionId) {
    if (sessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Must not be empty.');
    }
    final instance = _call(_delegate, 'getByName', <JSAny?>[sessionId.toJS]);
    return _CloudflareContainerInstance(_object(instance!));
  }
}

final class _CloudflareContainerInstance
    implements CloudflareContainerInstance {
  _CloudflareContainerInstance(this._delegate);

  final JSObject _delegate;

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    final response = await _promise(
      _call(_delegate, 'fetch', <JSAny?>[_nativeRequest(request)]),
    );
    if (response == null) {
      throw StateError('Cloudflare Container fetch() returned null.');
    }
    return _cloudflareResponseFromJavaScript(response);
  }
}

final class _CloudflareSecretsStoreBinding
    implements CloudflareSecretsStoreBinding {
  _CloudflareSecretsStoreBinding(this._delegate);

  final JSObject _delegate;

  @override
  Future<String?> get() async => _string(
    _dartify(
      await _promise(_callRpcMethod(_delegate, 'get', const <JSAny?>[])),
    ),
  );
}

final class _CloudflareWorkflow implements CloudflareWorkflow {
  _CloudflareWorkflow(this._delegate);

  final JSObject _delegate;

  @override
  Future<CloudflareWorkflowInstance> create({
    CloudflareWorkflowCreateOptions? options,
  }) async {
    final value = await _promise(
      _call(_delegate, 'create', <JSAny?>[
        if (options != null) _workflowCreateOptions(options),
      ]),
    );
    return _CloudflareWorkflowInstance(_object(value!));
  }

  @override
  Future<List<CloudflareWorkflowInstance>> createBatch(
    Iterable<CloudflareWorkflowCreateOptions> options,
  ) async {
    final value = await _promise(
      _call(_delegate, 'createBatch', <JSAny?>[
        options.map(_workflowCreateOptions).toList().jsify(),
      ]),
    );
    return _list(
      value,
    ).whereType<JSObject>().map(_CloudflareWorkflowInstance.new).toList();
  }

  @override
  Future<CloudflareWorkflowInstance> get(String id) async {
    final value = await _promise(_call(_delegate, 'get', <JSAny?>[id.toJS]));
    return _CloudflareWorkflowInstance(_object(value!));
  }
}

JSAny? _workflowCreateOptions(CloudflareWorkflowCreateOptions options) =>
    _jsify({
      if (options.id != null) 'id': options.id,
      if (options.params != null) 'params': options.params,
      if (options.successRetention != null || options.errorRetention != null)
        'retention': {
          if (options.successRetention != null)
            'successRetention': options.successRetention,
          if (options.errorRetention != null)
            'errorRetention': options.errorRetention,
        },
    });

final class _CloudflareWorkflowInstance implements CloudflareWorkflowInstance {
  _CloudflareWorkflowInstance(this._delegate);

  final JSObject _delegate;

  @override
  String get id => _string(_dartify(_property(_delegate, 'id'))) ?? '';

  @override
  Future<CloudflareWorkflowStatus> status() async => _workflowStatus(
    _dartify(await _promise(_call(_delegate, 'status', const <JSAny?>[]))),
  );

  @override
  Future<void> pause() async {
    await _promise(_call(_delegate, 'pause', const <JSAny?>[]));
  }

  @override
  Future<void> resume() async {
    await _promise(_call(_delegate, 'resume', const <JSAny?>[]));
  }

  @override
  Future<void> restart({CloudflareWorkflowRestartOptions? options}) async {
    await _promise(
      _call(_delegate, 'restart', <JSAny?>[
        if (options != null) _workflowRestartOptions(options),
      ]),
    );
  }

  @override
  Future<void> terminate({CloudflareWorkflowTerminateOptions? options}) async {
    await _promise(
      _call(_delegate, 'terminate', <JSAny?>[
        if (options != null) _workflowTerminateOptions(options),
      ]),
    );
  }

  @override
  Future<void> sendEvent({required String type, Object? payload}) async {
    await _promise(
      _call(_delegate, 'sendEvent', <JSAny?>[
        _jsify({'type': type, 'payload': payload}),
      ]),
    );
  }
}

JSAny? _workflowRestartOptions(CloudflareWorkflowRestartOptions options) {
  final from = options.from;
  return _jsify({
    if (from != null)
      'from': {
        'name': from.name,
        if (from.count != null) 'count': from.count,
        if (from.type != null) 'type': from.type,
      },
  });
}

JSAny? _workflowTerminateOptions(CloudflareWorkflowTerminateOptions options) =>
    _jsify({if (options.rollback != null) 'rollback': options.rollback});

final class _CloudflareContainer implements CloudflareContainer {
  _CloudflareContainer(this._delegate);

  final JSObject _delegate;

  @override
  bool get running => _dartify(_property(_delegate, 'running')) == true;

  @override
  void start({CloudflareContainerStartOptions? options}) {
    _call(_delegate, 'start', <JSAny?>[
      if (options != null) _containerStartOptions(options),
    ]);
  }

  @override
  Future<CloudflareContainerProcess> exec(
    Iterable<String> command, {
    CloudflareContainerExecOptions? options,
  }) async {
    final args = command.toList(growable: false);
    if (args.isEmpty) {
      throw ArgumentError.value(command, 'command', 'Must not be empty.');
    }
    final value = await _promise(
      _call(_delegate, 'exec', <JSAny?>[
        args.jsify(),
        if (options != null) _containerExecOptions(options),
      ]),
    );
    return _CloudflareContainerProcess(_object(value!));
  }

  @override
  Future<void> destroy([String? error]) async {
    await _promise(
      _call(_delegate, 'destroy', <JSAny?>[if (error != null) error.toJS]),
    );
  }

  @override
  void signal(int signal) {
    _call(_delegate, 'signal', <JSAny?>[signal.toJS]);
  }

  @override
  Future<void> monitor() async {
    await _promise(_call(_delegate, 'monitor', const <JSAny?>[]));
  }

  @override
  CloudflareContainerTcpPort getTcpPort(int port) =>
      _CloudflareContainerTcpPort(
        _object(_call(_delegate, 'getTcpPort', <JSAny?>[port.toJS])!),
      );
}

final class _CloudflareContainerProcess implements CloudflareContainerProcess {
  _CloudflareContainerProcess(this._delegate);

  final JSObject _delegate;

  @override
  int get pid => _int(_dartify(_property(_delegate, 'pid'))) ?? 0;

  @override
  Future<int> get exitCode async {
    final value = await _promise(_property(_delegate, 'exitCode'));
    return _int(_dartify(value)) ?? 0;
  }

  @override
  Future<CloudflareContainerExecOutput> output() async {
    final value = _map(
      _dartify(await _promise(_call(_delegate, 'output', const <JSAny?>[]))),
    );
    return CloudflareContainerExecOutput(
      stdout: _containerBytes(value['stdout']),
      stderr: _containerBytes(value['stderr']),
      exitCode: _int(value['exitCode']) ?? 0,
    );
  }

  @override
  void kill([int? signal]) {
    _call(_delegate, 'kill', <JSAny?>[if (signal != null) signal.toJS]);
  }
}

final class _CloudflareContainerTcpPort implements CloudflareContainerTcpPort {
  _CloudflareContainerTcpPort(this._delegate);

  final JSObject _delegate;

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    final response = await _promise(
      _call(_delegate, 'fetch', <JSAny?>[_nativeRequest(request)]),
    );
    if (response == null) {
      throw StateError('Cloudflare Container TCP port fetch() returned null.');
    }
    return _cloudflareResponseFromJavaScript(response);
  }
}

final class _CloudflareDurableObjectNamespace
    implements CloudflareDurableObjectNamespace {
  _CloudflareDurableObjectNamespace(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareDurableObjectId newUniqueId({String? jurisdiction}) {
    final options = jurisdiction == null
        ? null
        : _jsify(<String, Object?>{'jurisdiction': jurisdiction});
    return _CloudflareDurableObjectId(
      _object(_call(_delegate, 'newUniqueId', <JSAny?>[?options])!),
    );
  }

  @override
  CloudflareDurableObjectId idFromName(String name) =>
      _CloudflareDurableObjectId(
        _object(_call(_delegate, 'idFromName', <JSAny?>[name.toJS])!),
      );

  @override
  CloudflareDurableObjectId idFromString(String id) =>
      _CloudflareDurableObjectId(
        _object(_call(_delegate, 'idFromString', <JSAny?>[id.toJS])!),
      );

  @override
  CloudflareDurableObjectStub get(
    CloudflareDurableObjectId id, {
    String? locationHint,
  }) {
    final nativeId = _nativeId(id);
    final options = locationHint == null
        ? null
        : _jsify(<String, Object?>{'locationHint': locationHint});
    return _CloudflareDurableObjectStub(
      _object(_call(_delegate, 'get', <JSAny?>[nativeId, ?options])!),
    );
  }

  @override
  CloudflareDurableObjectStub getByName(String name, {String? locationHint}) {
    final options = locationHint == null
        ? null
        : _jsify(<String, Object?>{'locationHint': locationHint});
    return _CloudflareDurableObjectStub(
      _object(_call(_delegate, 'getByName', <JSAny?>[name.toJS, ?options])!),
    );
  }
}

JSObject _nativeId(CloudflareDurableObjectId id) {
  if (id is! _CloudflareDurableObjectId) {
    throw ArgumentError.value(
      id,
      'id',
      'The ID must come from this Durable Object namespace.',
    );
  }
  return id._delegate;
}

final class _CloudflareDurableObjectId implements CloudflareDurableObjectId {
  _CloudflareDurableObjectId(this._delegate);

  final JSObject _delegate;

  @override
  String? get name => _string(_dartify(_property(_delegate, 'name')));

  @override
  bool equals(CloudflareDurableObjectId other) =>
      _dartify(_call(_delegate, 'equals', <JSAny?>[_nativeId(other)])) == true;

  @override
  String toString() =>
      _string(_dartify(_call(_delegate, 'toString', const <JSAny?>[]))) ?? '';
}

final class _CloudflareDurableObjectStub
    implements CloudflareDurableObjectStub {
  _CloudflareDurableObjectStub(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareDurableObjectId get id =>
      _CloudflareDurableObjectId(_object(_property(_delegate, 'id')!));

  @override
  String? get name => _string(_dartify(_property(_delegate, 'name')));

  @override
  Future<CloudflareResponse> fetch(CloudflareRequest request) async {
    final response = await _promise(
      _call(_delegate, 'fetch', <JSAny?>[_nativeRequest(request)]),
    );
    if (response == null) {
      throw StateError('Durable Object fetch() returned null.');
    }
    return _cloudflareResponseFromJavaScript(response);
  }
}

final class _CloudflareDurableObjectState
    implements CloudflareDurableObjectState {
  _CloudflareDurableObjectState(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareDurableObjectId get id =>
      _CloudflareDurableObjectId(_object(_property(_delegate, 'id')!));

  @override
  CloudflareDurableObjectStorage get storage => _CloudflareDurableObjectStorage(
    _object(_property(_delegate, 'storage')!),
  );

  @override
  CloudflareContainer? get container {
    final value = _property(_delegate, 'container');
    return value is JSObject ? _CloudflareContainer(value) : null;
  }

  @override
  void waitUntil(Future<void> future) {
    _call(_delegate, 'waitUntil', <JSAny?>[future.toJS]);
  }

  @override
  Future<T> blockConcurrencyWhile<T>(Future<T> Function() callback) async {
    final result = await _promise(
      _call(_delegate, 'blockConcurrencyWhile', <JSAny?>[
        (() => callback().then((value) => _jsify(value)).toJS).toJS,
      ]),
    );
    return _dartify(result) as T;
  }

  @override
  void acceptWebSocket(
    CloudflareWebSocket webSocket, {
    Iterable<String> tags = const [],
  }) {
    _call(_delegate, 'acceptWebSocket', <JSAny?>[
      _nativeWebSocket(webSocket),
      if (tags.isNotEmpty) tags.toList().jsify(),
    ]);
  }

  @override
  List<CloudflareWebSocket> getWebSockets({String? tag}) {
    final value = _call(_delegate, 'getWebSockets', <JSAny?>[
      if (tag != null) tag.toJS,
    ]);
    if (value is! JSArray) return const <CloudflareWebSocket>[];
    return value.toDart
        .whereType<JSObject>()
        .map(_CloudflareWebSocket.new)
        .toList();
  }

  @override
  List<String> getTags(CloudflareWebSocket webSocket) => _list(
    _dartify(
      _call(_delegate, 'getTags', <JSAny?>[_nativeWebSocket(webSocket)]),
    ),
  ).whereType<String>().toList();

  @override
  void abort([String? reason]) {
    _call(_delegate, 'abort', <JSAny?>[if (reason != null) reason.toJS]);
  }
}

final class _CloudflareDurableObjectStorage
    implements CloudflareDurableObjectStorage {
  _CloudflareDurableObjectStorage(this._delegate);

  final JSObject _delegate;

  JSAny? _options(Map<String, Object?> values) =>
      values.isEmpty ? null : _jsify(values);

  Future<Object?> _asyncCall(String method, Iterable<JSAny?> arguments) async =>
      _dartify(await _promise(_call(_delegate, method, arguments)));

  @override
  Future<T?> get<T>(
    String key, {
    bool? allowConcurrency,
    bool? noCache,
  }) async =>
      (await _asyncCall('get', <JSAny?>[
            key.toJS,
            _options({
              'allowConcurrency': ?allowConcurrency,
              'noCache': ?noCache,
            }),
          ]))
          as T?;

  @override
  Future<Map<String, T>> getEntries<T>(
    Iterable<String> keys, {
    bool? allowConcurrency,
    bool? noCache,
  }) async {
    final value = await _asyncCall('get', <JSAny?>[
      _jsify(keys.toList()),
      _options({'allowConcurrency': ?allowConcurrency, 'noCache': ?noCache}),
    ]);
    return _map(value).map((key, value) => MapEntry(key, value as T));
  }

  @override
  Future<void> put<T>(
    String key,
    T value, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  }) async {
    await _asyncCall('put', <JSAny?>[
      key.toJS,
      _jsify(value),
      _options({
        'allowConcurrency': ?allowConcurrency,
        'allowUnconfirmed': ?allowUnconfirmed,
        'noCache': ?noCache,
      }),
    ]);
  }

  @override
  Future<void> putEntries<T>(
    Map<String, T> entries, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  }) async {
    await _asyncCall('put', <JSAny?>[
      _jsify(entries),
      _options({
        'allowConcurrency': ?allowConcurrency,
        'allowUnconfirmed': ?allowUnconfirmed,
        'noCache': ?noCache,
      }),
    ]);
  }

  @override
  Future<bool> delete(
    String key, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  }) async =>
      (await _asyncCall('delete', <JSAny?>[
            key.toJS,
            _options({
              'allowConcurrency': ?allowConcurrency,
              'allowUnconfirmed': ?allowUnconfirmed,
              'noCache': ?noCache,
            }),
          ]))
          as bool? ??
      false;

  @override
  Future<void> deleteAll({
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  }) async {
    await _asyncCall('deleteAll', <JSAny?>[
      _options({
        'allowConcurrency': ?allowConcurrency,
        'allowUnconfirmed': ?allowUnconfirmed,
        'noCache': ?noCache,
      }),
    ]);
  }

  @override
  Future<bool> deleteEntries(
    Iterable<String> keys, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  }) async =>
      (await _asyncCall('delete', <JSAny?>[
            _jsify(keys.toList()),
            _options({
              'allowConcurrency': ?allowConcurrency,
              'allowUnconfirmed': ?allowUnconfirmed,
              'noCache': ?noCache,
            }),
          ]))
          as bool? ??
      false;

  @override
  Future<Map<String, T>> list<T>({
    String? start,
    String? startAfter,
    String? end,
    String? prefix,
    bool? reverse,
    int? limit,
    bool? allowConcurrency,
    bool? noCache,
  }) async {
    final value = await _asyncCall('list', <JSAny?>[
      _options({
        'start': ?start,
        'startAfter': ?startAfter,
        'end': ?end,
        'prefix': ?prefix,
        'reverse': ?reverse,
        'limit': ?limit,
        'allowConcurrency': ?allowConcurrency,
        'noCache': ?noCache,
      }),
    ]);
    return _map(value).map((key, value) => MapEntry(key, value as T));
  }

  @override
  Future<int?> getAlarm({bool? allowConcurrency}) async => _int(
    await _asyncCall('getAlarm', <JSAny?>[
      _options({'allowConcurrency': ?allowConcurrency}),
    ]),
  );

  @override
  Future<void> setAlarm(
    DateTime scheduledTime, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
  }) async {
    await _asyncCall('setAlarm', <JSAny?>[
      scheduledTime.millisecondsSinceEpoch.toJS,
      _options({
        'allowConcurrency': ?allowConcurrency,
        'allowUnconfirmed': ?allowUnconfirmed,
      }),
    ]);
  }

  @override
  Future<void> deleteAlarm({
    bool? allowConcurrency,
    bool? allowUnconfirmed,
  }) async {
    await _asyncCall('deleteAlarm', <JSAny?>[
      _options({
        'allowConcurrency': ?allowConcurrency,
        'allowUnconfirmed': ?allowUnconfirmed,
      }),
    ]);
  }

  @override
  Future<void> sync() async {
    await _asyncCall('sync', const <JSAny?>[]);
  }

  @override
  CloudflareDurableObjectSqlStorage? get sql {
    final sql = _property(_delegate, 'sql');
    return sql == null
        ? null
        : _CloudflareDurableObjectSqlStorage(_object(sql));
  }
}

final class _CloudflareDurableObjectSqlStorage
    implements CloudflareDurableObjectSqlStorage {
  _CloudflareDurableObjectSqlStorage(this._delegate);

  final JSObject _delegate;

  @override
  CloudflareDurableObjectSqlResult exec(
    String query, [
    Iterable<Object?> parameters = const [],
  ]) {
    final result = _call(_delegate, 'exec', <JSAny?>[
      query.toJS,
      for (final parameter in parameters) _jsify(parameter),
    ]);
    return _CloudflareDurableObjectSqlResult(_object(result!));
  }
}

final class _CloudflareDurableObjectSqlResult
    implements CloudflareDurableObjectSqlResult {
  _CloudflareDurableObjectSqlResult(this._delegate);

  final JSObject _delegate;

  Object? _invoke(String method) =>
      _dartify(_call(_delegate, method, const <JSAny?>[]));

  @override
  List<Map<String, Object?>> toArray() =>
      _list(_invoke('toArray')).map(_map).toList();

  @override
  Map<String, Object?> one() => _map(_invoke('one'));

  @override
  List<Object?> raw() => _list(_invoke('raw'));

  @override
  void run() {
    _call(_delegate, 'run', const <JSAny?>[]);
  }
}

// This adapter is intentionally private; Durable Object state is supplied by
// the Worker runtime when a class is registered by a generated entrypoint.
/// Performs the cloudflareDurableObjectStateFromJavaScript operation.
CloudflareDurableObjectState cloudflareDurableObjectStateFromJavaScript(
  Object state,
) => _CloudflareDurableObjectState(_object(state));

/// Registers Durable Object factories for a JavaScript Worker module wrapper.
void defineCloudflareDurableObjects(
  Map<String, CloudflareDurableObjectFactory> factories,
) {
  final registry = JSObject();
  for (final entry in factories.entries) {
    if (entry.key.trim().isEmpty) {
      throw ArgumentError.value(
        entry.key,
        'factories',
        'Durable Object class names must not be empty.',
      );
    }
    final factory = entry.value;
    final constructor = ((JSAny state, JSAny environment) {
      final durableObject = factory(
        cloudflareDurableObjectStateFromJavaScript(state),
        cloudflareEnvironmentFromJavaScript(environment),
      );
      final delegate = JSObject();
      delegate.setProperty(
        'fetch'.toJS,
        ((JSAny request) {
          final response = durableObject.fetch(
            _CloudflareRequest(request as web.Request),
          );
          if (response is Future<CloudflareResponse>) {
            return response.then(_nativeResponse).toJS;
          }
          return _nativeResponse(response);
        }).toJS,
      );
      delegate.setProperty(
        'alarm'.toJS,
        (() {
          final result = durableObject.alarm();
          if (result is Future<void>) return result.toJS;
          return null;
        }).toJS,
      );
      delegate.setProperty(
        'webSocketMessage'.toJS,
        ((JSAny webSocket, JSAny message) {
          final result = durableObject.webSocketMessage(
            _CloudflareWebSocket(webSocket as JSObject),
            _cloudflareWebSocketMessage(message),
          );
          if (result is Future<void>) return result.toJS;
          return null;
        }).toJS,
      );
      delegate.setProperty(
        'webSocketClose'.toJS,
        ((JSAny webSocket, JSAny code, JSAny reason, JSAny wasClean) {
          final result = durableObject.webSocketClose(
            _CloudflareWebSocket(webSocket as JSObject),
            _int(_dartify(code)) ?? 1000,
            _string(_dartify(reason)) ?? '',
            _dartify(wasClean) == true,
          );
          if (result is Future<void>) return result.toJS;
          return null;
        }).toJS,
      );
      delegate.setProperty(
        'webSocketError'.toJS,
        ((JSAny webSocket, JSAny error) {
          final value = _dartify(error);
          final result = durableObject.webSocketError(
            _CloudflareWebSocket(webSocket as JSObject),
            value is Object ? value : StateError('Cloudflare WebSocket error.'),
          );
          if (result is Future<void>) return result.toJS;
          return null;
        }).toJS,
      );
      return delegate;
    }).toJS;
    registry.setProperty(entry.key.toJS, constructor);
  }
  globalContext.setProperty(cloudflareDurableObjectRegistryName.toJS, registry);
}
