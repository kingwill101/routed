library;

import 'dart:io';

import 'package:server_testing/server_testing.dart';

import '../_support/real_browser_bootstrap.dart';

// Single-test variant using browserTest helper
void main() {
  group('Browser test variant', () {
    late TestClient client;
    late String baseUrl;

    // Minimal server that renders a simple home page using dart:io
    Future<void> handleRequest(HttpRequest request) async {
      if (request.uri.path == '/' && request.method == 'GET') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<html><head><title>Home</title></head><body>Hi</body></html>',
          );
        await request.response.close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found');
        await request.response.close();
      }
    }

    setUpAll(() async {
      await realBrowserBootstrap(
        BrowserConfig(
          browserName: 'firefox',
          headless: true,
          baseUrl: 'http://127.0.0.1:0',
          autoScreenshots: false,
        ),
      );

      // Start ephemeral server and compute baseUrl then run a single browserTest
      final handler = IoRequestHandler(handleRequest);
      client = TestClient.ephemeralServer(handler);
      baseUrl = await client.baseUrlFuture;
    });

    tearDownAll(() async {
      await client.close();
      await realBrowserCleanup();
    });

    // Use the server base URL directly for this test.
    browserTest('single-test real browser variant', (browser) async {
      await browser.visit(baseUrl);
      await browser.assertTitle('Home');
    });
  });
}
