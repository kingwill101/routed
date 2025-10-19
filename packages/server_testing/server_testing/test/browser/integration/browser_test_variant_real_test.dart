@Tags(['real-browser'])
library;

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
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

  final engine = Engine()
    ..get(
      '/',
      (ctx) async => ctx.html(
        '<html><head><title>Home</title></head><body>Hi</body></html>',
      ),
    );

  // Start ephemeral server and compute baseUrl then run a single browserTest
  final handler = RoutedRequestHandler(engine);
  final client = TestClient.ephemeralServer(handler);
  final baseUrl = await client.baseUrlFuture;

  // Override baseUrl for this test only
  browserTest('single-test real browser variant', (browser) async {
    await browser.visit('/');
    await browser.assertTitle('Home');
  }, baseUrl: baseUrl);
}
