/// Integration between the Routed framework and the server_testing package.
///
/// This library provides utilities for testing Routed applications using
/// the server_testing package's fluent testing API.
///
/// ## Example
///
/// ```dart
/// import 'package:routed_core/routed_core.dart';
/// import 'package:routed_testing/routed_testing.dart';
/// import 'package:server_testing/server_testing.dart';
///
/// Future<void> main() async {
///   final engine = await Engine.create();
///   engine.get('/users', (ctx) => ctx.json({
///     'users': [{'name': 'Alice'}, {'name': 'Bob'}]
///   }));
///   final client = TestClient.inMemory(RoutedRequestHandler(engine));
///
///   final response = await client.get('/users');
///   response.assertStatus(200).assertJson((json) {
///     json.has('users').count('users', 2);
///   });
///
///   await client.close();
///   await engine.close();
/// }
/// ```
library;

export 'src/routed_transport.dart';
export 'src/testing.dart';
