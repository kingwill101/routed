import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Decodes a D1 result row into an application type.
typedef CloudflareD1RowDecoder<T> = T Function(Map<String, Object?> row);

/// Decodes a JSON value received from a Cloudflare request or response.
typedef CloudflareJsonDecoder<T> = T Function(Object? value);

/// Metadata returned by a D1 query.
final class CloudflareD1Meta {
  const CloudflareD1Meta({
    this.duration,
    this.rowsRead,
    this.rowsWritten,
    this.changes,
    this.changedDb,
    this.sizeAfter,
    this.lastRowId,
    this.servedBy,
    this.servedByPrimary,
    this.servedByRegion,
    this.servedByLocation,
    this.bookmark,
  });

  final num? duration;
  final int? rowsRead;
  final int? rowsWritten;
  final int? changes;
  final bool? changedDb;
  final int? sizeAfter;
  final Object? lastRowId;
  final String? servedBy;
  final String? servedByPrimary;
  final String? servedByRegion;
  final String? servedByLocation;
  final String? bookmark;
}

/// A D1 statement result.
final class CloudflareD1Result<T> {
  const CloudflareD1Result({
    required this.success,
    this.results = const <Never>[],
    this.meta,
    this.error,
  });

  final bool success;
  final List<T> results;
  final CloudflareD1Meta? meta;
  final Object? error;
}

/// The aggregate returned by D1's raw `exec` operation.
final class CloudflareD1ExecResult {
  const CloudflareD1ExecResult({required this.count, required this.duration});

  final int count;
  final num duration;
}

/// A Cloudflare Worker environment binding set.
abstract interface class CloudflareEnvironment {
  /// Returns the unwrapped binding with [name].
  Object binding(String name);

  /// Returns a KV namespace binding.
  CloudflareKvNamespace kv(String name);

  /// Returns a D1 database binding.
  CloudflareD1Database d1(String name);

  /// Returns a Durable Object namespace binding.
  CloudflareDurableObjectNamespace durableObjectNamespace(String name);

  /// Returns the Container binding identified by [name].
  ///
  /// A Container is addressed by a stable session ID. Use
  /// `env.container('APP_CONTAINER').get('session-id')` to obtain an instance
  /// and forward a request to it.
  CloudflareContainerBinding container(String name);

  /// Returns an R2 bucket binding.
  CloudflareR2Bucket r2(String name);

  /// Returns a Queue producer binding.
  CloudflareQueue queue(String name);

  /// Returns a Worker-to-Worker service binding.
  CloudflareServiceBinding service(String name);

  /// Returns a Worker-to-Worker service binding using the platform term.
  ///
  /// This is an alias of [service] for applications that describe their
  /// internal services as Worker bindings.
  CloudflareWorkerBinding worker(String name);

  /// Returns an account-level Secrets Store binding.
  CloudflareSecretsStoreBinding secretsStore(String name);

  /// Returns a Workflow binding.
  CloudflareWorkflow workflow(String name);
}

/// The request execution context supplied by a Cloudflare Worker.
abstract interface class CloudflareExecutionContext {
  /// Keeps asynchronous work alive after the response is returned.
  void waitUntil(Future<void> future);

  /// Requests that the platform pass through uncaught exceptions.
  void passThroughOnException();
}

/// A Fetch request represented without exposing the host's JavaScript types.
abstract interface class CloudflareRequest {
  String get method;

  String get url;

  Map<String, String> get headers;

  /// Cloudflare edge metadata attached to an incoming Worker request.
  ///
  /// This is empty for requests constructed with [createCloudflareRequest].
  /// Values are intentionally represented as Dart primitives and collections
  /// because the available keys vary by plan and Cloudflare feature set.
  Map<String, Object?> get cf;

  Future<String> text();

  Future<T?> json<T>({CloudflareJsonDecoder<T>? decode});
}

/// The Cache API for a Cloudflare edge cache namespace.
abstract interface class CloudflareCache {
  /// Finds a cached response for [request].
  Future<CloudflareResponse?> match(
    CloudflareRequest request, {
    bool ignoreMethod = false,
  });

  /// Stores [response] under [request]. The request must be a GET request.
  Future<void> put(CloudflareRequest request, CloudflareResponse response);

  /// Removes a cached response and reports whether an entry was removed.
  Future<bool> delete(CloudflareRequest request, {bool ignoreMethod = false});
}

/// Metadata and body returned by an R2 bucket operation.
final class CloudflareR2Object {
  const CloudflareR2Object({
    required this.key,
    this.version,
    this.size,
    this.etag,
    this.httpEtag,
    this.uploaded,
    this.httpMetadata = const <String, String>{},
    this.customMetadata = const <String, String>{},
    this.checksums = const <String, String>{},
    this.body,
  });

  final String key;
  final String? version;
  final int? size;
  final String? etag;
  final String? httpEtag;
  final DateTime? uploaded;
  final Map<String, String> httpMetadata;
  final Map<String, String> customMetadata;
  final Map<String, String> checksums;
  final Stream<List<int>>? body;

  /// Reads the object body into memory.
  Future<Uint8List> readAsBytes() async {
    final source = body;
    if (source == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Reads the object body as UTF-8 text.
  Future<String> readAsString() async => utf8.decode(await readAsBytes());
}

final class CloudflareR2ListOptions {
  const CloudflareR2ListOptions({
    this.limit,
    this.prefix,
    this.cursor,
    this.delimiter,
    this.include,
  });

  final int? limit;
  final String? prefix;
  final String? cursor;
  final String? delimiter;
  final List<String>? include;
}

final class CloudflareR2ListResult {
  const CloudflareR2ListResult({
    required this.objects,
    required this.truncated,
    this.cursor,
    this.delimitedPrefixes = const <String>[],
  });

  final List<CloudflareR2Object> objects;
  final bool truncated;
  final String? cursor;
  final List<String> delimitedPrefixes;
}

final class CloudflareR2PutOptions {
  const CloudflareR2PutOptions({
    this.httpMetadata = const <String, String>{},
    this.customMetadata = const <String, String>{},
  });

  final Map<String, String> httpMetadata;
  final Map<String, String> customMetadata;
}

/// An R2 object-storage bucket binding.
abstract interface class CloudflareR2Bucket {
  Future<CloudflareR2Object?> head(String key);

  Future<CloudflareR2Object?> get(String key);

  Future<CloudflareR2Object?> put(
    String key,
    Object? value, {
    CloudflareR2PutOptions? options,
  });

  /// Deletes one key or an iterable of keys.
  Future<void> delete(Object keys);

  Future<CloudflareR2ListResult> list({CloudflareR2ListOptions? options});
}

enum CloudflareQueueContentType { text, bytes, json, v8 }

final class CloudflareQueueMessage {
  const CloudflareQueueMessage(
    this.body, {
    this.contentType,
    this.delaySeconds,
  });

  final Object? body;
  final CloudflareQueueContentType? contentType;
  final int? delaySeconds;
}

final class CloudflareQueueMetrics {
  const CloudflareQueueMetrics({
    this.backlogCount,
    this.backlogBytes,
    this.oldestMessageTimestamp,
  });

  final int? backlogCount;
  final int? backlogBytes;
  final DateTime? oldestMessageTimestamp;
}

final class CloudflareQueueSendResult {
  const CloudflareQueueSendResult({this.metrics});

  final CloudflareQueueMetrics? metrics;
}

/// A Cloudflare Queue producer binding.
abstract interface class CloudflareQueue {
  Future<CloudflareQueueSendResult> send(
    Object? body, {
    CloudflareQueueContentType? contentType,
    int? delaySeconds,
  });

  Future<CloudflareQueueSendResult> sendBatch(
    Iterable<CloudflareQueueMessage> messages, {
    int? delaySeconds,
  });

  Future<CloudflareQueueMetrics> metrics();
}

/// A Worker-to-Worker service binding.
abstract interface class CloudflareServiceBinding {
  Future<CloudflareResponse> fetch(CloudflareRequest request);

  /// Calls an RPC method exposed by the bound Worker.
  ///
  /// RPC arguments and return values must be Cloudflare-compatible structured
  /// clone values. Use [decode] when the result should be converted to a
  /// typed application value.
  Future<T?> call<T>(
    String method, [
    Iterable<Object?> arguments = const [],
    CloudflareJsonDecoder<T>? decode,
  ]);
}

/// A Worker service binding, named after Cloudflare's Worker terminology.
typedef CloudflareWorkerBinding = CloudflareServiceBinding;

/// A binding for a Cloudflare Container namespace.
abstract interface class CloudflareContainerBinding {
  /// Gets a Container instance for [sessionId].
  CloudflareContainerInstance get(String sessionId);
}

/// A request-facing Container instance.
abstract interface class CloudflareContainerInstance {
  /// Forwards a Fetch request to the Container's default port.
  Future<CloudflareResponse> fetch(CloudflareRequest request);
}

/// Options used when starting a Container process.
final class CloudflareContainerStartOptions {
  const CloudflareContainerStartOptions({
    this.environment = const <String, String>{},
    this.entrypoint = const <String>[],
    this.enableInternet,
  });

  final Map<String, String> environment;
  final List<String> entrypoint;
  final bool? enableInternet;
}

/// Controls whether a Container process stream is captured.
enum CloudflareContainerStreamMode { pipe, ignore, combined }

/// Options used when executing a command in a running Container.
final class CloudflareContainerExecOptions {
  const CloudflareContainerExecOptions({
    this.stdout = CloudflareContainerStreamMode.pipe,
    this.stderr = CloudflareContainerStreamMode.pipe,
    this.environment = const <String, String>{},
    this.cwd,
    this.user,
  });

  final CloudflareContainerStreamMode stdout;
  final CloudflareContainerStreamMode stderr;
  final Map<String, String> environment;
  final String? cwd;
  final String? user;
}

/// Buffered output returned by a Container process.
final class CloudflareContainerExecOutput {
  const CloudflareContainerExecOutput({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final Uint8List stdout;
  final Uint8List stderr;
  final int exitCode;

  String get stdoutText => utf8.decode(stdout);

  String get stderrText => utf8.decode(stderr);
}

/// A process started inside a Cloudflare Container.
abstract interface class CloudflareContainerProcess {
  int get pid;

  Future<int> get exitCode;

  /// Reads the captured output once and waits for the process to exit.
  Future<CloudflareContainerExecOutput> output();

  /// Sends a signal to the process.
  void kill([int? signal]);
}

/// A TCP port exposed by a Container.
abstract interface class CloudflareContainerTcpPort {
  Future<CloudflareResponse> fetch(CloudflareRequest request);
}

/// Low-level Container controls exposed by a Container-backed Durable Object.
abstract interface class CloudflareContainer {
  bool get running;

  void start({CloudflareContainerStartOptions? options});

  Future<CloudflareContainerProcess> exec(
    Iterable<String> command, {
    CloudflareContainerExecOptions? options,
  });

  Future<void> destroy([String? error]);

  void signal(int signal);

  Future<void> monitor();

  CloudflareContainerTcpPort getTcpPort(int port);
}

/// An account-level secret exposed to a Worker through Secrets Store.
abstract interface class CloudflareSecretsStoreBinding {
  /// Reads the secret value. The value is never available through the
  /// management API; it is only returned by the bound Worker runtime.
  Future<String?> get();
}

/// Options for creating a Workflow instance.
final class CloudflareWorkflowCreateOptions {
  const CloudflareWorkflowCreateOptions({
    this.id,
    this.params,
    this.successRetention,
    this.errorRetention,
  });

  final String? id;
  final Object? params;
  final Object? successRetention;
  final Object? errorRetention;
}

/// Identifies a Workflow step when restarting an instance.
final class CloudflareWorkflowStepReference {
  const CloudflareWorkflowStepReference({
    required this.name,
    this.count,
    this.type,
  });

  final String name;
  final int? count;
  final String? type;
}

/// Options for restarting a Workflow instance.
final class CloudflareWorkflowRestartOptions {
  const CloudflareWorkflowRestartOptions({this.from});

  final CloudflareWorkflowStepReference? from;
}

/// Options for terminating a Workflow instance.
final class CloudflareWorkflowTerminateOptions {
  const CloudflareWorkflowTerminateOptions({this.rollback});

  final bool? rollback;
}

/// A Workflow error returned as part of instance status.
final class CloudflareWorkflowError {
  const CloudflareWorkflowError({required this.name, required this.message});

  final String name;
  final String message;
}

/// Rollback state returned as part of Workflow instance status.
final class CloudflareWorkflowRollback {
  const CloudflareWorkflowRollback({required this.outcome, this.error});

  final String outcome;
  final CloudflareWorkflowError? error;
}

/// The current status of a Workflow instance.
final class CloudflareWorkflowStatus {
  const CloudflareWorkflowStatus({
    required this.status,
    this.error,
    this.output,
    this.rollback,
  });

  final String status;
  final CloudflareWorkflowError? error;
  final Object? output;
  final CloudflareWorkflowRollback? rollback;
}

/// A running Workflow instance.
abstract interface class CloudflareWorkflowInstance {
  String get id;

  Future<CloudflareWorkflowStatus> status();

  Future<void> pause();

  Future<void> resume();

  Future<void> restart({CloudflareWorkflowRestartOptions? options});

  Future<void> terminate({CloudflareWorkflowTerminateOptions? options});

  Future<void> sendEvent({required String type, Object? payload});
}

/// A Cloudflare Workflow binding.
abstract interface class CloudflareWorkflow {
  Future<CloudflareWorkflowInstance> create({
    CloudflareWorkflowCreateOptions? options,
  });

  Future<List<CloudflareWorkflowInstance>> createBatch(
    Iterable<CloudflareWorkflowCreateOptions> options,
  );

  Future<CloudflareWorkflowInstance> get(String id);
}

/// A Fetch response represented without exposing the host's JavaScript types.
///
/// [body] is `null`, a [String], or a [Uint8List]. Responses returned by
/// Durable Object stubs are buffered at this boundary. A response with a
/// [webSocket] is a Cloudflare WebSocket upgrade response.
final class CloudflareResponse {
  const CloudflareResponse({
    this.body,
    this.status = 200,
    this.headers = const <String, String>{},
    this.webSocket,
  });

  factory CloudflareResponse.text(
    String body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) {
    return CloudflareResponse(
      body: body,
      status: status,
      headers: <String, String>{
        'content-type': 'text/plain; charset=utf-8',
        ...headers,
      },
    );
  }

  factory CloudflareResponse.json(
    Object? value, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) {
    return CloudflareResponse(
      body: jsonEncode(value),
      status: status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        ...headers,
      },
    );
  }

  factory CloudflareResponse.bytes(
    Uint8List body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) {
    return CloudflareResponse(body: body, status: status, headers: headers);
  }

  /// Creates a Cloudflare WebSocket upgrade response.
  ///
  /// The [webSocket] is normally the client side of a
  /// [CloudflareWebSocketPair]. The server side should be passed to
  /// [CloudflareDurableObjectState.acceptWebSocket].
  factory CloudflareResponse.webSocket(
    CloudflareWebSocket webSocket, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return CloudflareResponse(
      status: 101,
      headers: headers,
      webSocket: webSocket,
    );
  }

  final Object? body;
  final int status;
  final Map<String, String> headers;
  final CloudflareWebSocket? webSocket;

  bool get ok => status >= 200 && status < 300;

  bool get isWebSocketUpgrade => webSocket != null;

  String text() {
    final value = body;
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) return utf8.decode(value);
    throw StateError('Cloudflare response body is not text-compatible.');
  }

  T? json<T>({CloudflareJsonDecoder<T>? decode}) {
    final value = jsonDecode(text());
    return decode == null ? value as T? : decode(value);
  }
}

/// A WebSocket managed by the Cloudflare Durable Object hibernation API.
///
/// Text and binary messages are represented by [String] and [Uint8List]
/// respectively. The JavaScript WebSocket object is kept inside
/// `routed_node`; application code does not need `package:web` or
/// `dart:js_interop`.
abstract interface class CloudflareWebSocket {
  /// The WebSocket ready-state constant exposed by the Worker runtime.
  int get readyState;

  void send(Object data);

  void close([int? code, String? reason]);

  /// Stores an attachment that survives Durable Object hibernation.
  void serializeAttachment(Object? attachment);

  /// Reads the attachment stored by [serializeAttachment].
  T? deserializeAttachment<T>({CloudflareJsonDecoder<T>? decode});
}

/// The client/server WebSocket pair used to create a Fetch upgrade response.
abstract interface class CloudflareWebSocketPair {
  CloudflareWebSocket get client;

  CloudflareWebSocket get server;

  CloudflareResponse get response;
}

/// A Cloudflare KV namespace binding.
abstract interface class CloudflareKvNamespace {
  Future<String?> get(String key, {int? cacheTtl});

  Future<T?> getJson<T>(String key, {int? cacheTtl});

  Future<Uint8List?> getBytes(String key, {int? cacheTtl});

  Future<void> put(
    String key,
    Object value, {
    DateTime? expiration,
    int? expirationTtl,
    Object? metadata,
  });

  Future<void> delete(Iterable<String> keys);
}

/// A D1 database binding.
abstract interface class CloudflareD1Database {
  CloudflareD1PreparedStatement prepare(String query);

  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  });

  Future<CloudflareD1ExecResult> exec(String query);

  Future<Uint8List> dump();

  CloudflareD1DatabaseSession withSession({String? bookmark});
}

/// A prepared D1 SQL statement.
abstract interface class CloudflareD1PreparedStatement {
  CloudflareD1PreparedStatement bind([Iterable<Object?> values]);

  Future<CloudflareD1Result<T>> all<T>({CloudflareD1RowDecoder<T>? decode});

  Future<T?> first<T>({String? column, CloudflareD1RowDecoder<T>? decode});

  Future<CloudflareD1Result<T>> run<T>({CloudflareD1RowDecoder<T>? decode});

  Future<List<T>> raw<T>({CloudflareD1RowDecoder<T>? decode});
}

/// A sequential-consistency D1 session.
abstract interface class CloudflareD1DatabaseSession {
  CloudflareD1PreparedStatement prepare(String query);

  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  });

  Future<String?> getBookmark();
}

/// A Durable Object namespace binding.
abstract interface class CloudflareDurableObjectNamespace {
  CloudflareDurableObjectId newUniqueId({String? jurisdiction});

  CloudflareDurableObjectId idFromName(String name);

  CloudflareDurableObjectId idFromString(String id);

  CloudflareDurableObjectStub get(
    CloudflareDurableObjectId id, {
    String? locationHint,
  });

  CloudflareDurableObjectStub getByName(String name, {String? locationHint});
}

/// A Durable Object identifier.
abstract interface class CloudflareDurableObjectId {
  String? get name;

  bool equals(CloudflareDurableObjectId other);

  @override
  String toString();
}

/// A Durable Object request stub.
abstract interface class CloudflareDurableObjectStub {
  CloudflareDurableObjectId get id;

  String? get name;

  /// Sends a Fetch request to the object.
  ///
  /// The native Worker request and response are converted by `routed_node`.
  Future<CloudflareResponse> fetch(CloudflareRequest request);
}

/// A Durable Object implementation constructed for a Worker request.
abstract class CloudflareDurableObject {
  const CloudflareDurableObject(this.state, this.env);

  final CloudflareDurableObjectState state;
  final CloudflareEnvironment env;

  FutureOr<CloudflareResponse> fetch(CloudflareRequest request);

  FutureOr<void> alarm() {}

  /// Handles a message delivered by the Durable Object hibernation API.
  FutureOr<void> webSocketMessage(
    CloudflareWebSocket webSocket,
    Object message,
  ) {}

  /// Handles a WebSocket closed by the peer or by the Worker runtime.
  FutureOr<void> webSocketClose(
    CloudflareWebSocket webSocket,
    int code,
    String reason,
    bool wasClean,
  ) {}

  /// Handles a WebSocket error reported by the Worker runtime.
  FutureOr<void> webSocketError(CloudflareWebSocket webSocket, Object error) {}
}

/// Constructs a Durable Object from the state and environment supplied by
/// Cloudflare.
typedef CloudflareDurableObjectFactory =
    CloudflareDurableObject Function(
      CloudflareDurableObjectState state,
      CloudflareEnvironment env,
    );

/// Name of the JavaScript registry consumed by a Worker module wrapper.
const cloudflareDurableObjectRegistryName = '__routed_durable_objects__';

/// State available to a Durable Object instance.
abstract interface class CloudflareDurableObjectState {
  CloudflareDurableObjectId get id;

  CloudflareDurableObjectStorage get storage;

  /// Low-level Container controls when this Durable Object owns a Container.
  /// Ordinary Durable Objects return `null`.
  CloudflareContainer? get container;

  void waitUntil(Future<void> future);

  Future<T> blockConcurrencyWhile<T>(Future<T> Function() callback);

  /// Accepts a WebSocket using the Durable Object hibernation API.
  void acceptWebSocket(
    CloudflareWebSocket webSocket, {
    Iterable<String> tags = const [],
  });

  /// Returns hibernating WebSockets, optionally filtered by [tag].
  List<CloudflareWebSocket> getWebSockets({String? tag});

  /// Returns the tags attached to [webSocket].
  List<String> getTags(CloudflareWebSocket webSocket);

  void abort([String? reason]);
}

/// Legacy and SQLite-backed Durable Object storage.
abstract interface class CloudflareDurableObjectStorage {
  Future<T?> get<T>(String key, {bool? allowConcurrency, bool? noCache});

  Future<Map<String, T>> getEntries<T>(
    Iterable<String> keys, {
    bool? allowConcurrency,
    bool? noCache,
  });

  Future<void> put<T>(
    String key,
    T value, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  Future<void> putEntries<T>(
    Map<String, T> entries, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  Future<bool> delete(
    String key, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  Future<void> deleteAll({
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  Future<bool> deleteEntries(
    Iterable<String> keys, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  Future<Map<String, T>> list<T>({
    String? start,
    String? startAfter,
    String? end,
    String? prefix,
    bool? reverse,
    int? limit,
    bool? allowConcurrency,
    bool? noCache,
  });

  Future<int?> getAlarm({bool? allowConcurrency});

  Future<void> setAlarm(
    DateTime scheduledTime, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
  });

  Future<void> deleteAlarm({bool? allowConcurrency, bool? allowUnconfirmed});

  Future<void> sync();

  /// Returns the SQLite storage API when this object is backed by SQLite.
  CloudflareDurableObjectSqlStorage? get sql;
}

/// The synchronous SQLite API exposed by a SQLite-backed Durable Object.
abstract interface class CloudflareDurableObjectSqlStorage {
  CloudflareDurableObjectSqlResult exec(
    String query, [
    Iterable<Object?> parameters,
  ]);
}

/// A SQLite statement result. Methods mirror the current Workers SQL API.
abstract interface class CloudflareDurableObjectSqlResult {
  List<Map<String, Object?>> toArray();

  Map<String, Object?> one();

  List<Object?> raw();

  void run();
}
