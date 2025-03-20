/// Testing utilities for HTTP-based applications
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:server_testing/server_testing.dart';

/// Callback type for test functions that use [TestClient]
typedef TestCallback = Future<void> Function(TestClient client);

/// Creates a test that uses an [TestClient] to test HTTP endpoints.
///
/// This function is similar to [test] but automatically sets up an [TestClient]
/// with the provided [handler] and cleans it up after the test completes.
///
/// ## Parameters:
///
/// - [description]: Description of the test
/// - [callback]: Test function that receives an [TestClient]
/// - [handler]: The [RequestHandler] implementation that will process requests
/// - [transportMode]: The transport mode to use (in-memory or server)
/// - [timeout]: Optional timeout for the test
/// - [skip]: Whether to skip this test
/// - [tags]: Tags to apply to this test
/// - [onPlatform]: Platform-specific configuration
/// - [retry]: Number of times to retry this test if it fails
///
/// ## Example:
///
/// ```dart
/// import 'package:server_testing/server_testing.dart';
///
/// void main() {
///   // Create a handler for your application
///   final handler = MyApplicationHandler();
///
///   engineTest('GET /users returns a list of users', (client) async {
///     final response = await client.get('/users');
///
///     response
///         .assertStatus(200)
///         .assertJson((json) {
///           json.has('users');
///         });
///   }, handler: handler);
/// }
/// ```
@visibleForTesting
@isTest
void serverTest(
  String description,
  TestCallback callback, {
  required RequestHandler handler,
  TransportMode transportMode = TransportMode.inMemory,
  Timeout? timeout,
  Object? skip,
  Object? tags,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) {
  test(description, () async {
    // Initialize TestClient based on transport mode
    final client = transportMode == TransportMode.inMemory
        ? TestClient.inMemory(handler)
        : TestClient.ephemeralServer(handler);

    try {
      await callback(client);
    } catch (e, stack) {
      rethrow; // Rethrow to ensure test fails properly
    } finally {
      await client.close();
    }
  },
      timeout: timeout,
      skip: skip,
      tags: tags,
      onPlatform: onPlatform,
      retry: retry);
}
