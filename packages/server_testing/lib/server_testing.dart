/// A comprehensive testing utility package for Dart applications.
///
/// This package provides tools for testing HTTP endpoints, browser automation,
/// and JSON validation with a fluent, expressive API.
///
/// ## Main Components
///
/// * HTTP Testing - Test HTTP endpoints with [EngineTestClient]
/// * Browser Testing - Automate browser testing with the [Browser] interface
/// * JSON Assertions - Make assertions on JSON with [AssertableJson]
/// * Mocking Utilities - Mock HTTP requests and responses for testing
///
/// ## HTTP Testing Example
///
/// ```dart
/// import 'package:server_testing/server_testing.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   final handler = YourRequestHandler();
///
///   engineTest('GET /users returns user list', (client) async {
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
///
/// ## Browser Testing Example
///
/// ```dart
/// import 'package:server_testing/server_testing.dart';
///
/// void main() async {
///   final config = BrowserConfig(
///     browserName: 'firefox',
///     baseUrl: 'https://example.com',
///   );
///
///   await testBootstrap(config);
///
///   await browserTest('guest can view homepage', (browser) async {
///     await browser.visit('/');
///     await browser.assertTitle('Example Domain');
///   }, config: config);
/// }
/// ```
library;

export 'package:test/test.dart';

export 'extension.dart';
export 'mock.dart';
export 'src/browser/exports.dart';
export 'src/client.dart';
export 'testing.dart';
