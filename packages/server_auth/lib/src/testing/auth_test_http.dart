import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A fully buffered request captured by [AuthTestHttpClient].
final class AuthTestHttpRequest {
  /// Creates a captured request.
  const AuthTestHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  /// HTTP method exactly as sent by the auth client.
  final String method;

  /// Absolute request URI.
  final Uri uri;

  /// Request headers.
  final Map<String, String> headers;

  /// UTF-8 request body.
  final String body;

  /// Decodes [body] as a JSON object.
  Map<String, dynamic> jsonObject() {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final value = jsonDecode(body);
    if (value is! Map) {
      throw const FormatException('Auth test request was not a JSON object');
    }
    return Map<String, dynamic>.from(value);
  }
}

/// A framework-neutral response returned by an auth test responder.
final class AuthTestHttpResponse {
  /// Creates a raw response.
  const AuthTestHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  /// Creates a JSON response.
  factory AuthTestHttpResponse.json(
    Object? value, {
    int statusCode = 200,
    Map<String, String> headers = const <String, String>{},
  }) => AuthTestHttpResponse(
    statusCode: statusCode,
    body: jsonEncode(value),
    headers: <String, String>{'content-type': 'application/json', ...headers},
  );

  /// Creates the bounded public error shape consumed by [AuthClientTransport].
  factory AuthTestHttpResponse.error(
    String code, {
    int statusCode = 400,
    String? message,
    Map<String, String> headers = const <String, String>{},
  }) => AuthTestHttpResponse.json(
    <String, dynamic>{'error': code, 'message': ?message},
    statusCode: statusCode,
    headers: headers,
  );

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Produces one scripted auth response.
typedef AuthTestHttpResponder =
    FutureOr<AuthTestHttpResponse> Function(AuthTestHttpRequest request);

final class _AuthTestHttpStep {
  const _AuthTestHttpStep({
    required this.method,
    required this.path,
    required this.responder,
  });

  final String method;
  final String path;
  final AuthTestHttpResponder responder;
}

/// Deterministic `package:http` client for auth client and provider tests.
///
/// Responses are consumed in order. Every request is captured before its
/// responder runs, so [AuthTestGate] can pause a request while another request
/// enters the fixture. Use [enqueueFailure] or [enqueueOneTimeJson] for error
/// and replay scenarios.
final class AuthTestHttpClient extends http.BaseClient {
  /// Creates a scripted client with an optional [fallback] responder.
  AuthTestHttpClient({AuthTestHttpResponder? fallback}) : _fallback = fallback;

  final Queue<_AuthTestHttpStep> _steps = Queue<_AuthTestHttpStep>();
  final List<AuthTestHttpRequest> _requests = <AuthTestHttpRequest>[];
  final AuthTestHttpResponder? _fallback;
  var _closed = false;

  /// Captured requests in arrival order.
  List<AuthTestHttpRequest> get requests =>
      List<AuthTestHttpRequest>.unmodifiable(_requests);

  /// Number of scripted responses not yet consumed.
  int get pendingResponses => _steps.length;

  /// Adds a custom response for [method] and [path].
  void enqueue({
    required String method,
    required String path,
    required AuthTestHttpResponder respond,
  }) {
    _steps.add(
      _AuthTestHttpStep(
        method: method.toUpperCase(),
        path: _normalizePath(path),
        responder: respond,
      ),
    );
  }

  /// Adds a JSON response and optionally validates the decoded request body.
  void enqueueJson({
    required String method,
    required String path,
    required Object? response,
    Object? expectedRequest,
    int statusCode = 200,
    Map<String, String> headers = const <String, String>{},
  }) {
    enqueue(
      method: method,
      path: path,
      respond: (request) {
        if (expectedRequest != null) {
          final actual = request.jsonObject();
          if (jsonEncode(actual) != jsonEncode(expectedRequest)) {
            throw StateError(
              'Unexpected auth request JSON for ${request.uri.path}: '
              '${jsonEncode(actual)}',
            );
          }
        }
        return AuthTestHttpResponse.json(
          response,
          statusCode: statusCode,
          headers: headers,
        );
      },
    );
  }

  /// Adds a public auth error response.
  void enqueueFailure({
    required String method,
    required String path,
    required String code,
    int statusCode = 400,
    String? message,
    Map<String, String> headers = const <String, String>{},
  }) {
    enqueue(
      method: method,
      path: path,
      respond: (_) => AuthTestHttpResponse.error(
        code,
        statusCode: statusCode,
        message: message,
        headers: headers,
      ),
    );
  }

  /// Adds one success followed by a replay rejection for the same operation.
  void enqueueOneTimeJson({
    required String method,
    required String path,
    required Object? response,
    Object? expectedRequest,
    String replayCode = 'already_used',
    int replayStatusCode = 409,
  }) {
    enqueueJson(
      method: method,
      path: path,
      response: response,
      expectedRequest: expectedRequest,
    );
    enqueueFailure(
      method: method,
      path: path,
      code: replayCode,
      statusCode: replayStatusCode,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw StateError('AuthTestHttpClient is closed');
    final bytes = await request.finalize().toBytes();
    final captured = AuthTestHttpRequest(
      method: request.method.toUpperCase(),
      uri: request.url,
      headers: Map<String, String>.unmodifiable(request.headers),
      body: utf8.decode(bytes),
    );
    _requests.add(captured);

    AuthTestHttpResponder? responder;
    if (_steps.isNotEmpty) {
      final step = _steps.removeFirst();
      if (step.method != captured.method ||
          step.path != _normalizePath(captured.uri.path)) {
        throw StateError(
          'Expected ${step.method} ${step.path}, got '
          '${captured.method} ${captured.uri.path}',
        );
      }
      responder = step.responder;
    } else {
      responder = _fallback;
    }
    if (responder == null) {
      throw StateError(
        'No auth test response for ${captured.method} ${captured.uri.path}',
      );
    }
    final response = await responder(captured);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => _closed = true;
}

String _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}
