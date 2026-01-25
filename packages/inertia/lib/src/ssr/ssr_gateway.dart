library;

import 'ssr_response.dart';

/// Defines the interface for SSR gateways.
///
/// ```dart
/// final response = await gateway.render(pageJson);
/// ```
abstract class SsrGateway {
  /// Renders [pageJson] and returns the SSR response.
  Future<SsrResponse> render(String pageJson);

  /// Performs a health check against the SSR server.
  Future<bool> healthCheck();
}
