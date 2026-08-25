import 'package:routed_core/routed_core.dart';

import '../runtime/lifecycle.dart';
import '../runtime/runtime.dart';

/// Host-neutral view of a Fetch-style request.
///
/// JavaScript host entrypoints adapt their native request object to this view;
/// the Routed engine never imports a host's Fetch or execution-context types.
abstract interface class FetchRequestView {
  /// HTTP method supplied by the host request.
  String get method;

  /// Request URL as supplied by the host.
  String get url;

  /// Host header values before conversion to [PortableHeaders].
  Map<String, Object?> get rawHeaders;

  /// Request body bytes.
  Stream<List<int>> get body;

  /// Connecting client address, when the host exposes one.
  String? get remoteAddress;

  /// Request-scoped runtime context supplied by the host adapter.
  RoutedNodeContext? get hostContext;
}

/// Host-neutral response value produced for Fetch-style hosts.
final class FetchResponseView {
  /// Creates a response view for a Fetch-style host.
  FetchResponseView({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// HTTP status code to send to the client.
  final int statusCode;

  /// Response headers, preserving repeated values.
  final Map<String, List<String>> headers;

  /// Response body bytes produced by the engine.
  final Stream<List<int>> body;
}

/// Defines the public contract for this host integration.
final class FetchWebSocketUpgrade {
  /// Describes the result of accepting a Fetch WebSocket upgrade.
  FetchWebSocketUpgrade({
    required this.socket,
    required this.response,
    this.responseContainsWebSocket = false,
  });

  /// Routed WebSocket exposed to application code.
  final RoutedWebSocket socket;

  /// Native response object used to complete the host handshake.
  final Object response;

  /// Whether [response] already contains the platform WebSocket response.
  final bool responseContainsWebSocket;
}

final class _FetchRequestAdapter
    implements RequestAdapter, WebSocketUpgradeRequest, HostContextCarrier {
  _FetchRequestAdapter(
    FetchRequestView request, {
    Uri? baseUri,
    Future<FetchWebSocketUpgrade> Function()? accept,
  }) : _portable = portableRequestFromFetch(request, baseUri: baseUri),
       _accept = accept;

  final PortableRequest _portable;
  final Future<FetchWebSocketUpgrade> Function()? _accept;
  FetchWebSocketUpgrade? _upgrade;

  @override
  Object? get hostContext => _portable.hostContext;

  @override
  bool get isWebSocketUpgrade =>
      _accept != null &&
      _portable.method.toUpperCase() == 'GET' &&
      _portable.headers.get('upgrade')?.toLowerCase() == 'websocket' &&
      (_portable.headers
              .get('connection')
              ?.toLowerCase()
              .split(',')
              .map((value) => value.trim())
              .contains('upgrade') ??
          false);

  @override
  Object? get nativeUpgradeResponse => _upgrade?.response;

  @override
  Future<RoutedWebSocket> accept() async {
    _upgrade ??= _accept == null
        ? throw UnsupportedError('Fetch WebSocket upgrade is not configured.')
        : await _accept();
    return _upgrade!.socket;
  }

  @override
  String get method => _portable.method;

  @override
  Uri get uri => _portable.uri;

  @override
  Map<String, List<String>> get headers => _portable.headers.asMap;

  @override
  Stream<List<int>> get body => _portable.body;

  @override
  String? get remoteAddress => _portable.remoteAddress;
}

/// Converts a Fetch-style request into the core portable request contract.
PortableRequest portableRequestFromFetch(
  FetchRequestView request, {
  Uri? baseUri,
}) {
  final raw = request.url.isEmpty ? '/' : request.url;
  final base = baseUri ?? Uri(scheme: 'https', host: 'localhost');
  final headers = PortableHeaders();
  request.rawHeaders.forEach((name, value) {
    if (value == null) return;
    if (value is Iterable) {
      headers.setAll(name, value.map((item) => '$item').toList());
    } else {
      headers.set(name, '$value');
    }
  });

  return PortableRequest(
    method: request.method.isEmpty ? 'GET' : request.method,
    uri: base.resolve(raw),
    headers: headers,
    body: request.body,
    remoteAddress: request.remoteAddress,
    hostContext: request.hostContext,
  );
}

/// Dispatches a Fetch-style request through the streaming adapter path.
///
/// Hosts can implement [ResponseAdapter] over a native response stream to
/// preserve progressive writes. This path does not buffer the full response.
Future<void> dispatchFetchConnection(
  Engine engine,
  FetchRequestView request,
  ResponseAdapter response, {
  required RoutedNodeRuntimeInfo runtime,
  Uri? baseUri,
  Future<FetchWebSocketUpgrade> Function()? acceptWebSocket,
}) async {
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.requestStarted,
      info: runtime,
    ),
  );

  try {
    await engine.handleConnection(
      HttpConnection(
        _FetchRequestAdapter(
          request,
          baseUri: baseUri,
          accept: acceptWebSocket,
        ),
        response,
      ),
    );
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.requestFinished,
        info: runtime,
      ),
    );
  } catch (error, stackTrace) {
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.requestFailed,
        info: runtime,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    rethrow;
  }
}

/// Dispatches a Fetch-style request through Routed's buffered portable path.
Future<FetchResponseView> dispatchFetchExchange(
  Engine engine,
  FetchRequestView request, {
  required RoutedNodeRuntimeInfo runtime,
  Uri? baseUri,
}) async {
  publishRoutedNodeLifecycle(
    engine,
    RoutedNodeLifecycleEvent(
      phase: RoutedNodeLifecyclePhase.requestStarted,
      info: runtime,
    ),
  );

  try {
    final response = await engine.handlePortable(
      portableRequestFromFetch(request, baseUri: baseUri),
    );
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.requestFinished,
        info: runtime,
      ),
    );
    return FetchResponseView(
      statusCode: response.statusCode,
      headers: response.headers.asMap,
      body: response.body,
    );
  } catch (error, stackTrace) {
    publishRoutedNodeLifecycle(
      engine,
      RoutedNodeLifecycleEvent(
        phase: RoutedNodeLifecyclePhase.requestFailed,
        info: runtime,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    rethrow;
  }
}
