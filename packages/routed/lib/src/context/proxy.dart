part of 'context.dart';

/// Extension for proxy-related functionality
extension ProxyMethods on EngineContext {
  /// Forwards the current request to a target URL
  ///
  /// Parameters:
  /// - targetUrl: The URL to forward the request to
  /// - options: Optional configuration for the proxy request
  Future<Response> forward(String targetUrl, {ProxyOptions? options}) async {
    final client = HttpClient();
    try {
      final targetUri = Uri.parse(targetUrl);
      final proxyRequest = await client.openUrl(request.method, targetUri);

      // Forward original headers if enabled
      if (options?.forwardHeaders ?? true) {
        request.headers.forEach((name, values) {
          proxyRequest.headers.set(name, values.join(','));
        });
      }

      // Add standard proxy headers
      proxyRequest.headers.set('X-Forwarded-For', request.clientIP);
      proxyRequest.headers.set('X-Forwarded-Host', request.host);
      proxyRequest.headers.set('X-Forwarded-Proto', request.scheme);

      // Add custom headers
      options?.headers?.forEach((key, value) {
        proxyRequest.headers.set(key, value);
      });

      // Forward request body if it exists
      if (request.contentLength > 0) {
        proxyRequest.contentLength = request.contentLength;
        await proxyRequest.addStream(request.stream);
      }

      final proxyResponse = await proxyRequest.close();

      // Forward response status and headers
      response.statusCode = proxyResponse.statusCode;
      proxyResponse.headers.forEach((name, values) {
        response.headers.add(name, values.join(','));
      });

      // Add proxy identifier if configured
      if (options?.addProxyHeaders ?? true) {
        response.headers.add('X-Proxied-By', 'Routed');
      }

      // Stream response body
      await response.addStream(proxyResponse);
      return response;
    } finally {
      client.close();
    }
  }
}

/// Configuration options for proxy requests
class ProxyOptions {
  /// Whether to forward original request headers
  final bool forwardHeaders;

  /// Additional headers to add to the proxied request
  final Map<String, String>? headers;

  /// Whether to add proxy-related headers to the response
  final bool addProxyHeaders;

  /// Creates proxy options with the given configuration
  const ProxyOptions({
    this.forwardHeaders = true,
    this.headers,
    this.addProxyHeaders = true,
  });
}
