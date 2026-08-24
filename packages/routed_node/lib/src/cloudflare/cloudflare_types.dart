import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Decodes a D1 result row into an application type.
typedef CloudflareD1RowDecoder<T> = T Function(Map<String, Object?> row);

/// Decodes a JSON value received from a Cloudflare request or response.
typedef CloudflareJsonDecoder<T> = T Function(Object? value);

/// Metadata returned by a D1 query.
final class CloudflareD1Meta {
  /// Creates a CloudflareD1Meta value.
  const CloudflareD1Meta({
    this.duration,
    this.rowsRead,
    this.rowsWritten,
    this.changes,
    this.changedDb,
    this.sizeAfter,
    this.lastRowId,
    this.servedBy,
    this.servedByColo,
    this.servedByPrimary,
    this.servedByRegion,
    this.servedByLocation,
    this.bookmark,
  });

  /// The duration value.
  final num? duration;

  /// The rowsRead value.
  final int? rowsRead;

  /// The rowsWritten value.
  final int? rowsWritten;

  /// The changes value.
  final int? changes;

  /// The changedDb value.
  final bool? changedDb;

  /// The sizeAfter value.
  final int? sizeAfter;

  /// The lastRowId value.
  final Object? lastRowId;

  /// The servedBy value.
  final String? servedBy;

  /// The servedByColo value.
  final String? servedByColo;

  /// The servedByPrimary value.
  final bool? servedByPrimary;

  /// The servedByRegion value.
  final String? servedByRegion;

  /// The servedByLocation value.
  final String? servedByLocation;

  /// The bookmark value.
  final String? bookmark;
}

/// A D1 statement result.
final class CloudflareD1Result<T> {
  /// Creates a CloudflareD1Result value.
  const CloudflareD1Result({
    required this.success,
    this.results = const <Never>[],
    this.meta,
    this.error,
  });

  /// The success value.
  final bool success;

  /// The results value.
  final List<T> results;

  /// The meta value.
  final CloudflareD1Meta? meta;

  /// The error value.
  final Object? error;
}

/// The aggregate returned by D1's raw `exec` operation.
final class CloudflareD1ExecResult {
  /// Creates a CloudflareD1ExecResult value.
  const CloudflareD1ExecResult({required this.count, required this.duration});

  /// The count value.
  final int count;

  /// The duration value.
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
  /// The method value.
  String get method;

  /// The url value.
  String get url;

  /// The headers value.
  Map<String, String> get headers;

  /// Cloudflare edge metadata attached to an incoming Worker request.
  ///
  /// This is empty for requests constructed with `createCloudflareRequest`.
  /// Values are intentionally represented as Dart primitives and collections
  /// because the available keys vary by plan and Cloudflare feature set.
  Map<String, Object?> get cf;

  /// Performs the text operation.
  Future<String> text();

  /// Provides the declared Cloudflare API member.
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
  /// Creates a CloudflareR2Object value.
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

  /// The key value.
  final String key;

  /// The version value.
  final String? version;

  /// The size value.
  final int? size;

  /// The etag value.
  final String? etag;

  /// The httpEtag value.
  final String? httpEtag;

  /// The uploaded value.
  final DateTime? uploaded;

  /// The httpMetadata value.
  final Map<String, String> httpMetadata;

  /// The customMetadata value.
  final Map<String, String> customMetadata;

  /// The checksums value.
  final Map<String, String> checksums;

  /// The body value.
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

/// Configuration or result data used by the Cloudflare API.
final class CloudflareR2ListOptions {
  /// Creates a CloudflareR2ListOptions value.
  const CloudflareR2ListOptions({
    this.limit,
    this.prefix,
    this.cursor,
    this.delimiter,
    this.include,
  });

  /// The limit value.
  final int? limit;

  /// The prefix value.
  final String? prefix;

  /// The cursor value.
  final String? cursor;

  /// The delimiter value.
  final String? delimiter;

  /// The include value.
  final List<String>? include;
}

/// Configuration or result data used by the Cloudflare API.
final class CloudflareR2ListResult {
  /// Creates a CloudflareR2ListResult value.
  const CloudflareR2ListResult({
    required this.objects,
    required this.truncated,
    this.cursor,
    this.delimitedPrefixes = const <String>[],
  });

  /// The objects value.
  final List<CloudflareR2Object> objects;

  /// The truncated value.
  final bool truncated;

  /// The cursor value.
  final String? cursor;

  /// The delimitedPrefixes value.
  final List<String> delimitedPrefixes;
}

/// Configuration or result data used by the Cloudflare API.
final class CloudflareR2PutOptions {
  /// Creates a CloudflareR2PutOptions value.
  const CloudflareR2PutOptions({
    this.httpMetadata = const <String, String>{},
    this.customMetadata = const <String, String>{},
  });

  /// The httpMetadata value.
  final Map<String, String> httpMetadata;

  /// The customMetadata value.
  final Map<String, String> customMetadata;
}

/// An R2 object-storage bucket binding.
abstract interface class CloudflareR2Bucket {
  /// Performs the head operation.
  Future<CloudflareR2Object?> head(String key);

  /// Performs the get operation.
  Future<CloudflareR2Object?> get(String key);

  /// Performs the put operation.
  Future<CloudflareR2Object?> put(
    String key,
    Object? value, {
    CloudflareR2PutOptions? options,
  });

  /// Deletes one key or an iterable of keys.
  Future<void> delete(Object keys);

  /// Performs the list operation.
  Future<CloudflareR2ListResult> list({CloudflareR2ListOptions? options});
}

/// The serialization format used for a queued message body.
enum CloudflareQueueContentType {
  /// A UTF-8 text message.
  text,

  /// A byte sequence.
  bytes,

  /// A JSON-encoded message.
  json,

  /// A V8-serialized value.
  v8,
}

/// Configuration or result data used by the Cloudflare API.
final class CloudflareQueueMessage {
  /// Creates a CloudflareQueueMessage value.
  const CloudflareQueueMessage(
    this.body, {
    this.contentType,
    this.delaySeconds,
  });

  /// The body value.
  final Object? body;

  /// The contentType value.
  final CloudflareQueueContentType? contentType;

  /// The delaySeconds value.
  final int? delaySeconds;
}

/// Configuration or result data used by the Cloudflare API.
final class CloudflareQueueMetrics {
  /// Creates a CloudflareQueueMetrics value.
  const CloudflareQueueMetrics({
    this.backlogCount,
    this.backlogBytes,
    this.oldestMessageTimestamp,
  });

  /// The backlogCount value.
  final int? backlogCount;

  /// The backlogBytes value.
  final int? backlogBytes;

  /// The oldestMessageTimestamp value.
  final DateTime? oldestMessageTimestamp;
}

/// Configuration or result data used by the Cloudflare API.
final class CloudflareQueueSendResult {
  /// Creates a CloudflareQueueSendResult value.
  const CloudflareQueueSendResult({this.metrics});

  /// The metrics value.
  final CloudflareQueueMetrics? metrics;
}

/// A Cloudflare Queue producer binding.
abstract interface class CloudflareQueue {
  /// Performs the send operation.
  Future<CloudflareQueueSendResult> send(
    Object? body, {
    CloudflareQueueContentType? contentType,
    int? delaySeconds,
  });

  /// Performs the sendBatch operation.
  Future<CloudflareQueueSendResult> sendBatch(
    Iterable<CloudflareQueueMessage> messages, {
    int? delaySeconds,
  });

  /// Performs the metrics operation.
  Future<CloudflareQueueMetrics> metrics();
}

/// A Worker-to-Worker service binding.
abstract interface class CloudflareServiceBinding {
  /// Performs the fetch operation.
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
  /// Creates a CloudflareContainerStartOptions value.
  const CloudflareContainerStartOptions({
    this.environment = const <String, String>{},
    this.entrypoint = const <String>[],
    this.enableInternet,
  });

  /// The environment value.
  final Map<String, String> environment;

  /// The entrypoint value.
  final List<String> entrypoint;

  /// The enableInternet value.
  final bool? enableInternet;
}

/// Controls whether a Container process stream is captured.
/// Controls how a Container process stream is handled.
enum CloudflareContainerStreamMode {
  /// Forwards the stream to the caller.
  pipe,

  /// Discards the stream.
  ignore,

  /// Combines the stream with the other process stream.
  combined,
}

/// Options used when executing a command in a running Container.
final class CloudflareContainerExecOptions {
  /// Creates a CloudflareContainerExecOptions value.
  const CloudflareContainerExecOptions({
    this.stdout = CloudflareContainerStreamMode.pipe,
    this.stderr = CloudflareContainerStreamMode.pipe,
    this.environment = const <String, String>{},
    this.cwd,
    this.user,
  });

  /// The stdout value.
  final CloudflareContainerStreamMode stdout;

  /// The stderr value.
  final CloudflareContainerStreamMode stderr;

  /// The environment value.
  final Map<String, String> environment;

  /// The cwd value.
  final String? cwd;

  /// The user value.
  final String? user;
}

/// Buffered output returned by a Container process.
final class CloudflareContainerExecOutput {
  /// Creates a CloudflareContainerExecOutput value.
  const CloudflareContainerExecOutput({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// The stdout value.
  final Uint8List stdout;

  /// The stderr value.
  final Uint8List stderr;

  /// The exitCode value.
  final int exitCode;

  /// The stdoutText value.
  String get stdoutText => utf8.decode(stdout);

  /// The stderrText value.
  String get stderrText => utf8.decode(stderr);
}

/// A process started inside a Cloudflare Container.
abstract interface class CloudflareContainerProcess {
  /// The pid value.
  int get pid;

  /// The exitCode value.
  Future<int> get exitCode;

  /// Reads the captured output once and waits for the process to exit.
  Future<CloudflareContainerExecOutput> output();

  /// Sends a signal to the process.
  void kill([int? signal]);
}

/// A TCP port exposed by a Container.
abstract interface class CloudflareContainerTcpPort {
  /// Performs the fetch operation.
  Future<CloudflareResponse> fetch(CloudflareRequest request);
}

/// Low-level Container controls exposed by a Container-backed Durable Object.
abstract interface class CloudflareContainer {
  /// The running value.
  bool get running;

  /// Performs the start operation.
  void start({CloudflareContainerStartOptions? options});

  /// Performs the exec operation.
  Future<CloudflareContainerProcess> exec(
    Iterable<String> command, {
    CloudflareContainerExecOptions? options,
  });

  /// Performs the destroy operation.
  Future<void> destroy([String? error]);

  /// Performs the signal operation.
  void signal(int signal);

  /// Performs the monitor operation.
  Future<void> monitor();

  /// Performs the getTcpPort operation.
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
  /// Creates a CloudflareWorkflowCreateOptions value.
  const CloudflareWorkflowCreateOptions({
    this.id,
    this.params,
    this.successRetention,
    this.errorRetention,
  });

  /// The id value.
  final String? id;

  /// The params value.
  final Object? params;

  /// The successRetention value.
  final Object? successRetention;

  /// The errorRetention value.
  final Object? errorRetention;
}

/// Identifies a Workflow step when restarting an instance.
final class CloudflareWorkflowStepReference {
  /// Creates a CloudflareWorkflowStepReference value.
  const CloudflareWorkflowStepReference({
    required this.name,
    this.count,
    this.type,
  });

  /// The name value.
  final String name;

  /// The count value.
  final int? count;

  /// The type value.
  final String? type;
}

/// Options for restarting a Workflow instance.
final class CloudflareWorkflowRestartOptions {
  /// Creates a CloudflareWorkflowRestartOptions value.
  const CloudflareWorkflowRestartOptions({this.from});

  /// The from value.
  final CloudflareWorkflowStepReference? from;
}

/// Options for terminating a Workflow instance.
final class CloudflareWorkflowTerminateOptions {
  /// Creates a CloudflareWorkflowTerminateOptions value.
  const CloudflareWorkflowTerminateOptions({this.rollback});

  /// The rollback value.
  final bool? rollback;
}

/// A Workflow error returned as part of instance status.
final class CloudflareWorkflowError {
  /// Creates a CloudflareWorkflowError value.
  const CloudflareWorkflowError({required this.name, required this.message});

  /// The name value.
  final String name;

  /// The message value.
  final String message;
}

/// Rollback state returned as part of Workflow instance status.
final class CloudflareWorkflowRollback {
  /// Creates a CloudflareWorkflowRollback value.
  const CloudflareWorkflowRollback({required this.outcome, this.error});

  /// The outcome value.
  final String outcome;

  /// The error value.
  final CloudflareWorkflowError? error;
}

/// The current status of a Workflow instance.
final class CloudflareWorkflowStatus {
  /// Creates a CloudflareWorkflowStatus value.
  const CloudflareWorkflowStatus({
    required this.status,
    this.error,
    this.output,
    this.rollback,
  });

  /// The status value.
  final String status;

  /// The error value.
  final CloudflareWorkflowError? error;

  /// The output value.
  final Object? output;

  /// The rollback value.
  final CloudflareWorkflowRollback? rollback;
}

/// A running Workflow instance.
abstract interface class CloudflareWorkflowInstance {
  /// The id value.
  String get id;

  /// Performs the status operation.
  Future<CloudflareWorkflowStatus> status();

  /// Performs the pause operation.
  Future<void> pause();

  /// Performs the resume operation.
  Future<void> resume();

  /// Performs the restart operation.
  Future<void> restart({CloudflareWorkflowRestartOptions? options});

  /// Performs the terminate operation.
  Future<void> terminate({CloudflareWorkflowTerminateOptions? options});

  /// Performs the sendEvent operation.
  Future<void> sendEvent({required String type, Object? payload});
}

/// A Cloudflare Workflow binding.
abstract interface class CloudflareWorkflow {
  /// Performs the create operation.
  Future<CloudflareWorkflowInstance> create({
    CloudflareWorkflowCreateOptions? options,
  });

  /// Performs the createBatch operation.
  Future<List<CloudflareWorkflowInstance>> createBatch(
    Iterable<CloudflareWorkflowCreateOptions> options,
  );

  /// Performs the get operation.
  Future<CloudflareWorkflowInstance> get(String id);
}

/// A Fetch response represented without exposing the host's JavaScript types.
///
/// [body] is `null`, a [String], or a [Uint8List]. Responses returned by
/// Durable Object stubs are buffered at this boundary. A response with a
/// [webSocket] is a Cloudflare WebSocket upgrade response.
final class CloudflareResponse {
  /// Creates a CloudflareResponse value.
  const CloudflareResponse({
    this.body,
    this.status = 200,
    this.headers = const <String, String>{},
    this.webSocket,
  });

  /// Provides the declared Cloudflare API member.
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

  /// Provides the declared Cloudflare API member.
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

  /// Provides the declared Cloudflare API member.
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

  /// The body value.
  final Object? body;

  /// The status value.
  final int status;

  /// The headers value.
  final Map<String, String> headers;

  /// The webSocket value.
  final CloudflareWebSocket? webSocket;

  /// The ok value.
  bool get ok => status >= 200 && status < 300;

  /// The isWebSocketUpgrade value.
  bool get isWebSocketUpgrade => webSocket != null;

  /// Performs the text operation.
  String text() {
    final value = body;
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) return utf8.decode(value);
    throw StateError('Cloudflare response body is not text-compatible.');
  }

  /// Provides the declared Cloudflare API member.
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

  /// Performs the send operation.
  void send(Object data);

  /// Performs the close operation.
  void close([int? code, String? reason]);

  /// Stores an attachment that survives Durable Object hibernation.
  void serializeAttachment(Object? attachment);

  /// Reads the attachment stored by [serializeAttachment].
  T? deserializeAttachment<T>({CloudflareJsonDecoder<T>? decode});
}

/// The client/server WebSocket pair used to create a Fetch upgrade response.
abstract interface class CloudflareWebSocketPair {
  /// The client value.
  CloudflareWebSocket get client;

  /// The server value.
  CloudflareWebSocket get server;

  /// The response value.
  CloudflareResponse get response;
}

/// A Cloudflare KV namespace binding.
abstract interface class CloudflareKvNamespace {
  /// Performs the get operation.
  Future<String?> get(String key, {int? cacheTtl});

  /// Provides the declared Cloudflare API member.
  Future<T?> getJson<T>(String key, {int? cacheTtl});

  /// Performs the getBytes operation.
  Future<Uint8List?> getBytes(String key, {int? cacheTtl});

  /// Performs the put operation.
  Future<void> put(
    String key,
    Object value, {
    DateTime? expiration,
    int? expirationTtl,
    Object? metadata,
  });

  /// Performs the delete operation.
  Future<void> delete(Iterable<String> keys);
}

/// A D1 database binding.
abstract interface class CloudflareD1Database {
  /// Performs the prepare operation.
  CloudflareD1PreparedStatement prepare(String query);

  /// Provides the declared Cloudflare API member.
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  });

  /// Performs the exec operation.
  Future<CloudflareD1ExecResult> exec(String query);

  /// Performs the dump operation.
  Future<Uint8List> dump();

  /// Performs the withSession operation.
  CloudflareD1DatabaseSession withSession({String? bookmark});
}

/// A prepared D1 SQL statement.
abstract interface class CloudflareD1PreparedStatement {
  /// Performs the bind operation.
  CloudflareD1PreparedStatement bind([Iterable<Object?> values]);

  /// Provides the declared Cloudflare API member.
  Future<CloudflareD1Result<T>> all<T>({CloudflareD1RowDecoder<T>? decode});

  /// Provides the declared Cloudflare API member.
  Future<T?> first<T>({String? column, CloudflareD1RowDecoder<T>? decode});

  /// Provides the declared Cloudflare API member.
  Future<CloudflareD1Result<T>> run<T>({CloudflareD1RowDecoder<T>? decode});

  /// Provides the declared Cloudflare API member.
  Future<List<T>> raw<T>({CloudflareD1RowDecoder<T>? decode});
}

/// A sequential-consistency D1 session.
abstract interface class CloudflareD1DatabaseSession {
  /// Performs the prepare operation.
  CloudflareD1PreparedStatement prepare(String query);

  /// Provides the declared Cloudflare API member.
  Future<List<CloudflareD1Result<T>>> batch<T>(
    Iterable<CloudflareD1PreparedStatement> statements, {
    CloudflareD1RowDecoder<T>? decode,
  });

  /// Performs the getBookmark operation.
  Future<String?> getBookmark();
}

/// A Durable Object namespace binding.
abstract interface class CloudflareDurableObjectNamespace {
  /// Performs the newUniqueId operation.
  CloudflareDurableObjectId newUniqueId({String? jurisdiction});

  /// Performs the idFromName operation.
  CloudflareDurableObjectId idFromName(String name);

  /// Performs the idFromString operation.
  CloudflareDurableObjectId idFromString(String id);

  /// Performs the get operation.
  CloudflareDurableObjectStub get(
    CloudflareDurableObjectId id, {
    String? locationHint,
  });

  /// Performs the getByName operation.
  CloudflareDurableObjectStub getByName(String name, {String? locationHint});
}

/// A Durable Object identifier.
abstract interface class CloudflareDurableObjectId {
  /// The name value.
  String? get name;

  /// Performs the equals operation.
  bool equals(CloudflareDurableObjectId other);

  @override
  String toString();
}

/// A Durable Object request stub.
abstract interface class CloudflareDurableObjectStub {
  /// The id value.
  CloudflareDurableObjectId get id;

  /// The name value.
  String? get name;

  /// Sends a Fetch request to the object.
  ///
  /// The native Worker request and response are converted by `routed_node`.
  Future<CloudflareResponse> fetch(CloudflareRequest request);
}

/// A Durable Object implementation constructed for a Worker request.
abstract class CloudflareDurableObject {
  /// Creates a CloudflareDurableObject value.
  const CloudflareDurableObject(this.state, this.env);

  /// The state value.
  final CloudflareDurableObjectState state;

  /// The env value.
  final CloudflareEnvironment env;

  /// Performs the fetch operation.
  FutureOr<CloudflareResponse> fetch(CloudflareRequest request);

  /// Performs the alarm operation.
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
  /// The id value.
  CloudflareDurableObjectId get id;

  /// The storage value.
  CloudflareDurableObjectStorage get storage;

  /// Low-level Container controls when this Durable Object owns a Container.
  /// Ordinary Durable Objects return `null`.
  CloudflareContainer? get container;

  /// Performs the waitUntil operation.
  void waitUntil(Future<void> future);

  /// Provides the declared Cloudflare API member.
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

  /// Performs the abort operation.
  void abort([String? reason]);
}

/// Legacy and SQLite-backed Durable Object storage.
abstract interface class CloudflareDurableObjectStorage {
  /// Provides the declared Cloudflare API member.
  Future<T?> get<T>(String key, {bool? allowConcurrency, bool? noCache});

  /// Provides the declared Cloudflare API member.
  Future<Map<String, T>> getEntries<T>(
    Iterable<String> keys, {
    bool? allowConcurrency,
    bool? noCache,
  });

  /// Provides the declared Cloudflare API member.
  Future<void> put<T>(
    String key,
    T value, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  /// Provides the declared Cloudflare API member.
  Future<void> putEntries<T>(
    Map<String, T> entries, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  /// Performs the delete operation.
  Future<bool> delete(
    String key, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  /// Performs the deleteAll operation.
  Future<void> deleteAll({
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  /// Performs the deleteEntries operation.
  Future<bool> deleteEntries(
    Iterable<String> keys, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
    bool? noCache,
  });

  /// Provides the declared Cloudflare API member.
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

  /// Performs the getAlarm operation.
  Future<int?> getAlarm({bool? allowConcurrency});

  /// Performs the setAlarm operation.
  Future<void> setAlarm(
    DateTime scheduledTime, {
    bool? allowConcurrency,
    bool? allowUnconfirmed,
  });

  /// Performs the deleteAlarm operation.
  Future<void> deleteAlarm({bool? allowConcurrency, bool? allowUnconfirmed});

  /// Performs the sync operation.
  Future<void> sync();

  /// Returns the SQLite storage API when this object is backed by SQLite.
  CloudflareDurableObjectSqlStorage? get sql;
}

/// The synchronous SQLite API exposed by a SQLite-backed Durable Object.
abstract interface class CloudflareDurableObjectSqlStorage {
  /// Performs the exec operation.
  CloudflareDurableObjectSqlResult exec(
    String query, [
    Iterable<Object?> parameters,
  ]);
}

/// A SQLite statement result. Methods mirror the current Workers SQL API.
abstract interface class CloudflareDurableObjectSqlResult {
  /// Performs the toArray operation.
  List<Map<String, Object?>> toArray();

  /// Performs the one operation.
  Map<String, Object?> one();

  /// Performs the raw operation.
  List<Object?> raw();

  /// Performs the run operation.
  void run();
}
