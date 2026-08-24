import 'dart:async';
import 'dart:io' show HttpRequest, HttpResponse;

import 'package:routed_core/routed_core.dart' show PortableRequest;
import 'package:routed_core/src/engine/engine.dart' show Engine;
import 'package:routed_core/src/http/portable_message.dart'
    show PortableRequest;

/// A host-neutral WebSocket connection used by portable engine adapters.
abstract interface class RoutedWebSocket {
  /// The incoming and outgoing message stream.
  Stream<dynamic> get stream;

  /// The close code supplied by the peer, when available.
  int? get closeCode;

  /// Sends [data] to the peer.
  void add(dynamic data);

  /// Closes the connection with an optional [code] and [reason].
  Future<void> close([int? code, String? reason]);
}

/// A request that can accept a WebSocket upgrade without `dart:io`.
abstract interface class WebSocketUpgradeRequest {
  /// Whether the request asks to upgrade to WebSocket.
  bool get isWebSocketUpgrade;

  /// The native upgrade response, when supplied by the host.
  Object? get nativeUpgradeResponse;

  /// Accepts the upgrade and returns the portable WebSocket.
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
  /// The opaque host-owned request context.
  Object? get hostContext;
}

/// A request adapter used by Routed.
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
  /// Completes the host-specific upgrade using [nativeWebSocket].
  void upgrade(Object nativeWebSocket);
}

/// A response adapter used by Routed.
abstract interface class ResponseAdapter {
  /// The current response status code.
  int get statusCode;

  /// Updates the response status code.
  set statusCode(int value);

  /// Replaces a header value.
  void setHeader(String name, String value);

  /// Appends a header value.
  void addHeader(String name, String value);

  /// Writes response body bytes.
  void write(List<int> bytes);

  /// Flushes buffered response data.
  Future<void> flush();

  /// Closes the response.
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
/// types on their concrete connection class (for example, a native HTTP
/// request handle).
final class HttpConnection {
  /// Creates an exchange from matching [request] and [response] adapters.
  const HttpConnection(this.request, this.response);

  /// The inbound request adapter.
  final RequestAdapter request;

  /// The outbound response adapter.
  final ResponseAdapter response;
}

/// Options passed to [ServerTransport.serve].
class ServerOptions {
  /// Creates transport options for [host] and [port].
  const ServerOptions({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.shared = false,
  });

  /// The interface or hostname to bind.
  final String host;

  /// The port to bind.
  final int port;

  /// Whether the listener may share the underlying socket.
  final bool shared;
}

/// Handle returned by a transport after binding.
abstract interface class ServerHandle {
  /// Closes the server handle.
  Future<void> close({bool force = false});

  /// The bound host name or address.
  String get host;

  /// The bound port.
  int get port;
}

/// Pluggable server binding / event loop.
///
/// - `routed_io` implements bind/listen with `HttpServer`
/// - `routed_node` implements bind/listen with Node.js `http.createServer`
/// - Workers packages typically skip bind and call [Engine.handleConnection]
///   from a fetch handler instead
abstract interface class ServerTransport {
  /// Binds and starts the [engine] using [options].
  Future<ServerHandle> serve(Engine engine, ServerOptions options);
}
