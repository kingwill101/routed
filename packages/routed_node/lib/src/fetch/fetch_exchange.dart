import 'package:routed_core/routed_core.dart';

import '../runtime/lifecycle.dart';
import '../runtime/runtime.dart';

/// Host-neutral view of a Fetch-style request.
///
/// JavaScript host entrypoints adapt their native request object to this view;
/// the Routed engine never imports a host's Fetch or execution-context types.
abstract interface class FetchRequestView {
  String get method;
  String get url;
  Map<String, Object?> get rawHeaders;
  Stream<List<int>> get body;
  String? get remoteAddress;
  RoutedNodeContext? get hostContext;
}

/// Host-neutral response value produced for Fetch-style hosts.
final class FetchResponseView {
  FetchResponseView({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final Stream<List<int>> body;
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
