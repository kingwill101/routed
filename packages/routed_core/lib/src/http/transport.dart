import 'dart:async';

import 'package:routed_core/src/engine/engine.dart' show Engine;

/// A host-neutral WebSocket connection used by portable engine adapters.
abstract interface class RoutedWebSocket {
  Stream<dynamic> get stream;
  int? get closeCode;
  void add(dynamic data);
  Future<void> close([int? code, String? reason]);
}

/// A request that can accept a WebSocket upgrade without `dart:io`.
abstract interface class WebSocketUpgradeRequest {
  bool get isWebSocketUpgrade;
  Object? get nativeUpgradeResponse;
  Future<RoutedWebSocket> accept();
}

/// Minimal inbound HTTP message (host-agnostic).
///
/// Host packages implement this for their request type:
/// - `routed_io` wraps `dart:io` [HttpRequest]
/// - `routed_node` wraps Node.js `IncomingMessage`
/// - a Cloudflare adapter wraps the Workers `Request`
/// Optional opaque host context carried by a request adapter.
///
/// Core stores and forwards this value without inspecting it. Host packages
/// can use it to expose typed native request, response, or execution-context
/// extensions without importing host APIs into `routed_core`.
abstract interface class HostContextCarrier {
  Object? get hostContext;
}

abstract interface class RequestAdapter {
  /// HTTP method, e.g. GET.
  String get method;

  /// Request URI (path + query as presented to the app).
  Uri get uri;

  /// Multi-value headers.
  Map<String, List<String>> get headers;

  /// Request body stream.
  Stream<List<int>> get body;

  /// Remote address if known.
  String? get remoteAddress;
}

/// Minimal outbound HTTP response sink (host-agnostic).
///
/// Host packages implement this for their response type:
/// - `routed_io` wraps `dart:io` [HttpResponse]
/// - `routed_node` wraps Node.js `ServerResponse`
/// - a Cloudflare adapter builds a Workers `Response`
abstract interface class WebSocketResponseAdapter {
  void upgrade(Object nativeWebSocket);
}

abstract interface class ResponseAdapter {
  int get statusCode;
  set statusCode(int value);

  void setHeader(String name, String value);
  void addHeader(String name, String value);

  void write(List<int> bytes);
  Future<void> flush();
  Future<void> close();
}

/// Optional capability for host adapters that carry an opaque native request.
///
/// Optional IO fast-path only.
///
/// When [nativeRequest] is a `dart:io` [HttpRequest], [Engine.handleConnection]
/// skips the portable bridge (websockets, progressive writes). Portable hosts
/// (`routed_node`, Workers) must not implement this — use [PortableRequest] /
/// [Engine.handlePortable] instead.
abstract interface class NativeRequestHandle {
  /// Host-specific request object (e.g. `dart:io` [HttpRequest]).
  Object? get nativeRequest;

  /// Host-specific response object (e.g. `dart:io` [HttpResponse]).
  Object? get nativeResponse;
}

/// One inbound exchange: request + response adapters from the same host.
///
/// Core only depends on this pair; host packages may also expose raw platform
/// types on their concrete connection class (e.g. [IoHttpConnection.httpRequest]).
final class HttpConnection {
  const HttpConnection(this.request, this.response);

  final RequestAdapter request;
  final ResponseAdapter response;
}

/// Options passed to [ServerTransport.serve].
class ServerOptions {
  const ServerOptions({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.shared = false,
  });

  final String host;
  final int port;
  final bool shared;
}

/// Handle returned by a transport after binding.
abstract interface class ServerHandle {
  Future<void> close({bool force = false});
  String get host;
  int get port;
}

/// Pluggable server binding / event loop.
///
/// - `routed_io` implements bind/listen with `HttpServer`
/// - `routed_node` implements bind/listen with Node.js `http.createServer`
/// - Workers packages typically skip bind and call [Engine.handleConnection]
///   from a fetch handler instead
abstract interface class ServerTransport {
  Future<ServerHandle> serve(Engine engine, ServerOptions options);
}
