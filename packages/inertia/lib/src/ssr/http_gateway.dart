import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ssr_gateway.dart';
import 'ssr_response.dart';

/// HTTP implementation of the Inertia SSR gateway
class HttpSsrGateway implements SsrGateway {
  HttpSsrGateway(this.endpoint, {this.healthEndpoint, http.Client? client})
    : _client = client ?? http.Client();
  final Uri endpoint;
  final Uri? healthEndpoint;
  final http.Client _client;

  @override
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
    return SsrResponse(
      body: data['body'] as String? ?? '',
      head: data['head'] as String? ?? '',
      statusCode: response.statusCode,
    );
  }

  @override
  Future<bool> healthCheck() async {
    final checkUri = healthEndpoint ?? endpoint.resolve('/health');
    final response = await _client.get(checkUri);
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
