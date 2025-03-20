/// An adapter for the Shelf package to use server_testing for HTTP testing.
///
/// This library provides a [ShelfRequestHandler] that adapts a shelf.Handler
/// to the server_testing.RequestHandler interface, enabling fluent testing of
/// Shelf applications with the server_testing package.
///
/// ## Example
///
/// ```dart
/// import 'package:shelf/shelf.dart' as shelf;
/// import 'package:server_testing/server_testing.dart';
/// import 'package:server_testing_shelf/server_testing_shelf.dart';
///
/// void main() {
///   // Create your shelf application
///   final app = shelf.Pipeline()
///       .addMiddleware(shelf.logRequests())
///       .addHandler((request) {
///         if (request.url.path == 'users') {
///           return shelf.Response.ok(
///             '{"users": [{"name": "Alice"}, {"name": "Bob"}]}',
///             headers: {'content-type': 'application/json'},
///           );
///         }
///         return shelf.Response.notFound('Not found');
///       });
///
///   // Wrap your shelf app with ShelfRequestHandler
///   final handler = ShelfRequestHandler(app);
///
///   // Use with server_testing
///   engineTest('GET /users returns list of users', (client) async {
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

export 'src/shelf_request_handler.dart';
