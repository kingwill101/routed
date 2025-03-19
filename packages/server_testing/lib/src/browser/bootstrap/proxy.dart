import 'dart:io';

class ProxyConfiguration {
  final String host;
  final int port;
  final String? username;
  final String? password;

  const ProxyConfiguration({
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  HttpClient createClient() {
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY $host:$port';

    if (username != null && password != null) {
      client.addProxyCredentials(host, port, 'Basic',
          HttpClientBasicCredentials(username!, password!));
    }

    return client;
  }
}

class ProxyClient {
  final HttpClient _client;

  ProxyClient(ProxyConfiguration config) : _client = config.createClient();

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

  void close() {
    _client.close();
  }
}
