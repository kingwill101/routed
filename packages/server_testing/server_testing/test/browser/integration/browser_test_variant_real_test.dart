@Tags(['real-browser'])
library;

import 'dart:io';

import 'package:server_testing/server_testing.dart';

// Single-test variant using browserTest helper
void main() async {
  await testBootstrap(
    BrowserConfig(
      browserName: 'firefox',
      headless: false,
      baseUrl: 'http://127.0.0.1:0',
      autoScreenshots: false,
    ),
  );

  // Minimal server that renders a simple home page using dart:io
  Future<void> handleRequest(HttpRequest request) async {
    if (request.uri.path == '/' && request.method == 'GET') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('<html><head><title>Home</title></head><body>Hi</body></html>');
      await request.response.close();
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
    }
  }

  // Start ephemeral server and compute baseUrl then run a single browserTest
  final handler = IoRequestHandler(handleRequest);
  final client = TestClient.ephemeralServer(handler);
  final baseUrl = await client.baseUrlFuture;

  // Override baseUrl for this test only
  browserTest('single-test real browser variant', (browser) async {
    await browser.visit('/');
    await browser.assertTitle('Home');
  }, baseUrl: baseUrl);
}
