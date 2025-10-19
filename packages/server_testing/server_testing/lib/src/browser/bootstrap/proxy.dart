import 'dart:io';

/// Holds configuration details for connecting through an HTTP proxy server.
class ProxyConfiguration {
  /// The hostname or IP address of the proxy server.
  final String host;

  /// The port number of the proxy server.
  final int port;

  /// The username for proxy authentication (optional).
  final String? username;

  /// The password for proxy authentication (optional).
  final String? password;

  /// Creates a constant [ProxyConfiguration] instance.
  const ProxyConfiguration({
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  /// Creates and configures an [HttpClient] instance to use this proxy configuration.
  ///
  /// Sets the `findProxy` callback and adds basic authentication credentials
  /// if [username] and [password] are provided.
  HttpClient createClient() {
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY $host:$port';

    if (username != null && password != null) {
      client.addProxyCredentials(
        host,
        port,
        'Basic',
        HttpClientBasicCredentials(username!, password!),
      );
    }

    return client;
  }
}

/// A simple HTTP client wrapper that sends all requests through a configured proxy.
///
/// Uses an [HttpClient] configured by a [ProxyConfiguration].
class ProxyClient {
  /// The underlying [HttpClient] instance configured for proxy usage.
  final HttpClient _client;

  /// Creates a [ProxyClient] using the settings from the provided [config].
  ProxyClient(ProxyConfiguration config) : _client = config.createClient();

  /// Opens a connection to the target [url] via the configured proxy, using
  /// the specified HTTP [method].
  ///
  /// Optional [headers] and request [body] can be provided.
  /// Returns the [HttpClientResponse] from the server.
  Future<HttpClientResponse> send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final request = await _client.openUrl(method, url);

    if (headers != null) {
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });
    }

    if (body != null) {
      request.headers.contentLength = body.toString().length;
      request.write(body);
    }

    return await request.close();
  }

  /// Closes the underlying [HttpClient], releasing system resources.
  void close() {
    _client.close();
  }
}
