import 'dart:io';

import 'package:server_testing/server_testing.dart';

// Reproduces an issue where headers.set('Content-Type', ...) works under
// ephemeralServer transport but is ignored / replaced with text/plain under
// the inMemory transport mocking layer.
void main() {
  for (final mode in TransportMode.values) {
    test('headers.set content-type respected [$mode]', () async {
      final handler = IoRequestHandler((HttpRequest req) async {
        // Intentionally set BEFORE any body writes.
        req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
        req.response.write('<html>ok</html>');
        await req.response.close();
      });

      final client = TestClient(handler, mode: mode);
      final res = await client.get('/');
      res.assertStatus(200).assertHeaderContains('content-type', 'text/html');
      await client.close();
    });
  }
}
