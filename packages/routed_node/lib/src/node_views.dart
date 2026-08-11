// Platform-neutral views of Node.js HTTP types.
// JS interop bindings implement these; tests and stubs supply pure-Dart
// fakes. Core never sees Node types — only RequestAdapter/ResponseAdapter.

/// Node `http.IncomingMessage` surface used by [NodeRequestAdapter].
abstract interface class NodeIncomingView {
  /// HTTP method (e.g. `GET`).
  String get method;

  /// Request URL path + query (as Node provides on `req.url`).
  String get url;

  /// Raw header map. Values may be [String] or [List] of strings (Node style).
  Map<String, Object?> get rawHeaders;

  /// Remote socket address if known.
  String? get remoteAddress;

  /// Request body as bytes.
  Stream<List<int>> get body;
}

/// Node `http.ServerResponse` surface used by [NodeResponseAdapter].
abstract interface class NodeServerResponseView {
  /// Write status code (once, before body).
  void writeHead(int statusCode, Map<String, Object> headers);

  /// Append body chunk.
  void write(List<int> bytes);

  /// End the response (optional trailing chunk).
  void end([List<int>? bytes]);

  /// Whether [end] has been called.
  bool get finished;
}
