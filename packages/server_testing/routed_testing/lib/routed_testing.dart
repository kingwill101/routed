/// Integration between the Routed framework and the server_testing package.
///
/// This library provides utilities for testing Routed applications using
/// the server_testing package's fluent testing API.
///
/// ## Example
///
/// ```dart
/// import 'package:routed/routed.dart';
/// import 'package:routed_testing/routed_testing.dart';
/// import 'package:server_testing/server_testing.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   // Create a Routed engine with routes
///   final engine = Engine()
///     ..get('/hello', (req, res) => res.send('Hello, World!'))
///     ..get('/users', (req, res) => res.json({
///       'users': [{'name': 'Alice'}, {'name': 'Bob'}]
///     }));
///
///   // Create the handler
///   final handler = RoutedRequestHandler(engine);
///
///   // Test with server_testing
///   engineTest('GET /users returns user list', (client) async {
///     final response = await client.get('/users');
///
///     response
///       .assertStatus(200)
///       .assertJson((json) {
///         json.has('users').count('users', 2);
///       });
///   }, handler: handler);
/// }
/// ```
library;

export 'src/routed_transport.dart';
export 'testing.dart';
