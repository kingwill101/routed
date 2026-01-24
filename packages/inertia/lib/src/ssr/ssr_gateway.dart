import 'ssr_response.dart';

/// Interface for Inertia SSR gateways
abstract class SsrGateway {
  /// Render the page payload and return SSR response
  Future<SsrResponse> render(String pageJson);

  /// Perform a health check against the SSR server
  Future<bool> healthCheck();
}
