import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:routed_core/routed_core.dart' show Engine;
import 'package:routed_core/src/engine/engine.dart' show Engine;
import 'package:routed_core/src/http/transport.dart';

/// Multi-value HTTP headers without `dart:io` types.
///
/// Case-insensitive names; values are preserved in insertion order per name.
final class PortableHeaders {
  /// Creates headers populated with [initial] values.
  PortableHeaders([Map<String, List<String>>? initial]) {
    if (initial != null) {
      initial.forEach(setAll);
    }
  }

  final Map<String, List<String>> _values = <String, List<String>>{};
  final Map<String, String> _canonical = <String, String>{};

  /// Lower-cased name → values.
  Map<String, List<String>> get asMap {
    final out = <String, List<String>>{};
    _values.forEach((key, values) {
      out[key] = List<String>.from(values);
    });
    return out;
  }

  /// Returns all values for [name], or `null` when the header is absent.
  List<String>? operator [](String name) {
    final values = _values[_key(name)];
    return values == null ? null : List<String>.from(values);
  }

  /// Returns the values for [name] joined as one header string.
  String? get(String name) {
    final values = this[name];
    if (values == null || values.isEmpty) return null;
    return values.join(', ');
  }

  /// Replaces all values for [name] with [value].
  void set(String name, String value) {
    final key = _key(name);
    _canonical[key] = name;
    _values[key] = [value];
  }

  /// Replaces all values for [name].
  void setAll(String name, List<String> values) {
    final key = _key(name);
    _canonical[key] = name;
    _values[key] = List<String>.from(values);
  }

  /// Appends [value] to the values for [name].
  void add(String name, String value) {
    final key = _key(name);
    _canonical.putIfAbsent(key, () => name);
    _values.putIfAbsent(key, () => <String>[]).add(value);
  }

  /// Whether a value for [name] is present.
  bool contains(String name) => _values.containsKey(_key(name));

  /// Iterates over header names and defensive copies of their values.
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach((key, values) {
      action(_canonical[key] ?? key, List<String>.from(values));
    });
  }

  static String _key(String name) => name.toLowerCase();
}

/// Host-agnostic inbound HTTP message (value + body stream).
///
/// Built by host packages from their native request type, then passed to
/// [Engine.handlePortable] or wrapped as a [RequestAdapter].
final class PortableRequest {
  /// Creates a host-neutral request value.
  PortableRequest({
    required this.method,
    required this.uri,
    PortableHeaders? headers,
    Stream<List<int>>? body,
    this.remoteAddress,
    this.hostContext,
  }) : headers = headers ?? PortableHeaders(),
       body = body ?? const Stream.empty();

  /// Copy fields from any [RequestAdapter] (body stream is shared, not cloned).
  factory PortableRequest.fromAdapter(RequestAdapter adapter) {
    return PortableRequest(
      method: adapter.method,
      uri: adapter.uri,
      headers: PortableHeaders(adapter.headers),
      body: adapter.body,
      remoteAddress: adapter.remoteAddress,
      hostContext: adapter is HostContextCarrier
          ? (adapter as HostContextCarrier).hostContext
          : null,
    );
  }

  /// HTTP method (e.g. `GET`).
  final String method;

  /// Full request URI as seen by the app.
  final Uri uri;

  /// Request headers.
  final PortableHeaders headers;

  /// Body byte stream (single-consumer; hosts should not re-read).
  final Stream<List<int>> body;

  /// Client address when the host provides one.
  final String? remoteAddress;

  /// Opaque host-owned context forwarded without core inspection.
  final Object? hostContext;

  /// View this message as a [RequestAdapter] for [HttpConnection].
  RequestAdapter asAdapter() => _PortableRequestAdapter(this);
}

/// Host-agnostic outbound HTTP message (status, headers, body bytes/stream).
///
/// Produced by [Engine.handlePortable] or built by hosts that buffer responses.
final class PortableResponse {
  /// Creates a host-neutral response value.
  PortableResponse({
    this.statusCode = 200,
    PortableHeaders? headers,
    Stream<List<int>>? body,
    List<int>? bodyBytes,
  }) : headers = headers ?? PortableHeaders(),
       _bodyBytes = bodyBytes,
       _bodyStream = body;

  /// The HTTP status code.
  final int statusCode;

  /// The response headers.
  final PortableHeaders headers;
  final List<int>? _bodyBytes;
  final Stream<List<int>>? _bodyStream;

  /// Buffered body when the full payload is available.
  List<int>? get bodyBytes => _bodyBytes;

  /// Body as a stream (buffered bytes, live stream, or empty).
  Stream<List<int>> get body {
    final stream = _bodyStream;
    if (stream != null) return stream;
    final bytes = _bodyBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Stream<List<int>>.value(bytes);
    }
    return const Stream.empty();
  }

  /// Decode [bodyBytes] as UTF-8 when fully buffered.
  String? get bodyText {
    final bytes = _bodyBytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }
}

/// What a host claims to support. Not a promise of identical behavior everywhere.
final class HostCapabilities {
  /// Creates a capability description for a host.
  const HostCapabilities({
    this.streaming = true,
    this.websocket = false,
    this.fileSystem = false,
    this.backgroundWork = false,
  });

  /// Progressive response body writes.
  final bool streaming;

  /// HTTP upgrade / websocket accept.
  final bool websocket;

  /// Local filesystem access.
  final bool fileSystem;

  /// Work that may outlive the response (waitUntil-style).
  final bool backgroundWork;

  /// Capability set for a host with no optional features.
  static const HostCapabilities none = HostCapabilities();

  /// Capability set for a Dart IO process.
  static const HostCapabilities ioProcess = HostCapabilities(
    websocket: true,
    fileSystem: true,
    backgroundWork: true,
  );

  /// Capability set for a Node.js process.
  static const HostCapabilities nodeProcess = HostCapabilities(
    websocket: true,
    fileSystem: true,
    backgroundWork: true,
  );

  /// Capability set for an edge Fetch host.
  static const HostCapabilities edgeFetch = HostCapabilities(
    backgroundWork: true,
  );
}

/// [ResponseAdapter] that records status, headers, and body for
/// [PortableResponse] materialization.
final class RecordingResponseAdapter implements ResponseAdapter {
  /// Creates an empty response recorder.
  RecordingResponseAdapter();

  int _statusCode = 200;

  /// Creates a [RecordingResponseAdapter].
  final PortableHeaders headers = PortableHeaders();
  final BytesBuilder _body = BytesBuilder(copy: false);
  bool _closed = false;

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) {
    if (_closed) return;
    _statusCode = value;
  }

  @override
  void setHeader(String name, String value) {
    if (_closed) return;
    headers.set(name, value);
  }

  @override
  void addHeader(String name, String value) {
    if (_closed) return;
    headers.add(name, value);
  }

  @override
  void write(List<int> bytes) {
    if (_closed) {
      throw StateError('Cannot write to a closed recording response');
    }
    if (bytes.isNotEmpty) _body.add(bytes);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    _closed = true;
  }

  /// Whether the response has been closed.
  bool get isClosed => _closed;

  /// Materializes the recorded values as a portable response.
  PortableResponse toPortableResponse() {
    return PortableResponse(
      statusCode: _statusCode,
      headers: headers,
      bodyBytes: _body.takeBytes(),
    );
  }
}

/// Writes a [PortableResponse] into a [ResponseAdapter] sink.
Future<void> writePortableResponse(
  PortableResponse source,
  ResponseAdapter target,
) async {
  target.statusCode = source.statusCode;
  source.headers.forEach((name, values) {
    if (name.toLowerCase() == 'set-cookie') {
      for (final value in values) {
        target.addHeader(name, value);
      }
    } else if (values.length == 1) {
      target.setHeader(name, values.first);
    } else {
      target.setHeader(name, values.join(', '));
    }
  });
  await for (final chunk in source.body) {
    if (chunk.isNotEmpty) target.write(chunk);
  }
  await target.close();
}

final class _PortableRequestAdapter
    implements RequestAdapter, WebSocketUpgradeRequest, HostContextCarrier {
  _PortableRequestAdapter(this._request);

  final PortableRequest _request;

  @override
  Object? get hostContext => _request.hostContext;

  @override
  bool get isWebSocketUpgrade => false;

  @override
  Object? get nativeUpgradeResponse => null;

  @override
  Future<RoutedWebSocket> accept() => throw UnsupportedError(
    'Portable WebSocket upgrade requires a host adapter.',
  );

  @override
  String get method => _request.method;

  @override
  Uri get uri => _request.uri;

  @override
  Map<String, List<String>> get headers => _request.headers.asMap;

  @override
  Stream<List<int>> get body => _request.body;

  @override
  String? get remoteAddress => _request.remoteAddress;
}
