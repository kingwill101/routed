library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ssr_gateway.dart';
import 'ssr_response.dart';

/// Provides an HTTP-based SSR gateway implementation.
///
/// ```dart
/// final gateway = HttpSsrGateway(Uri.parse('http://127.0.0.1:13714'));
/// final ssr = await gateway.render(pageJson);
/// ```
class HttpSsrGateway implements SsrGateway {
  /// Creates a gateway targeting [endpoint].
  HttpSsrGateway(this.endpoint, {this.healthEndpoint, http.Client? client})
    : _client = client ?? http.Client();

  /// The SSR render endpoint.
  final Uri endpoint;

  /// Optional health check endpoint override.
  final Uri? healthEndpoint;
  final http.Client _client;

  @override
  /// Renders [pageJson] via POST and returns the SSR response.
  ///
  /// #### Throws
  /// - [StateError] when the SSR server returns a 4xx or 5xx response.
  Future<SsrResponse> render(String pageJson) async {
    final response = await _client.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: pageJson,
    );

    if (response.statusCode >= 400) {
      throw StateError(
        'SSR server returned ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final body = data['body'] as String? ?? '';
    final headValue = data['head'];
    final head = _normalizeHead(headValue);
    return SsrResponse(body: body, head: head, statusCode: response.statusCode);
  }

  @override
  /// Performs a health check against the SSR server.
  Future<bool> healthCheck() async {
    final checkUri = healthEndpoint ?? endpoint.resolve('/health');
    final response = await _client.get(checkUri);
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}

String _normalizeHead(dynamic head) {
  if (head is String) return head;
  if (head is Iterable) {
    return head.map((item) => item?.toString() ?? '').join('');
  }
  return '';
}
