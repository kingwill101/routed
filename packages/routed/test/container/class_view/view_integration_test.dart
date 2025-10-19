void main() {}

// import 'package:routed/routed.dart';
// import 'package:routed_testing/routed_testing.dart';
// import 'package:server_testing/server_testing.dart';
//
// class CounterView extends View {
//   int counter = 0;
//
//   @override
//   Future<void> get(EngineContext context) async {
//     context.string('Counter: $counter');
//   }
//
//   @override
//   Future<void> post(EngineContext context) async {
//     counter++;
//     context.string('Counter incremented to: $counter');
//   }
//
//   @override
//   Future<void> delete(EngineContext context) async {
//     counter = 0;
//     context.string('Counter reset to: $counter');
//   }
//
//   @override
//   List<String> get allowedMethods => ['GET', 'POST', 'DELETE'];
// }
//
// class ApiView extends View {
//   final Map<String, dynamic> data = {
//     'users': [
//       {'id': 1, 'name': 'Alice'},
//       {'id': 2, 'name': 'Bob'},
//     ]
//   };
//
//   @override
//   Future<void> get(EngineContext context) async {
//     context.json(data);
//   }
//
//   @override
//   Future<void> post(EngineContext context) async {
//     // In a real app, we would parse the request body
//     data['users'].add({'id': 3, 'name': 'Charlie'});
//     context.json({'status': 'success', 'message': 'User added'});
//   }
// }
//
// class ParameterizedView extends View {
//   @override
//   Future<void> get(EngineContext context) async {
//     final id = context.param('id');
//     context.string('ID: $id');
//   }
// }
//
// void main() {
//   group('View Integration Tests', () {
//     TestClient? client;
//
//     tearDown(() async {
//       await client?.close();
//     });
//
//     test('Basic View Registration', () async {
//       final engine = Engine();
//       final router = Router();
//
//       // Register a view
//       router.view('/counter', CounterView());
//       engine.use(router);
//
//       client = TestClient(RoutedRequestHandler(engine));
//
//       // Test GET request
//       final getResponse = await client!.get('/counter');
//       getResponse
//         ..assertStatus(200)
//         ..assertBodyContains('Counter: 0');
//
//       // Test POST request
//       final postResponse = await client!.post('/counter', null);
//       postResponse
//         ..assertStatus(200)
//         ..assertBodyContains('Counter incremented to: 1');
//
//       // Test DELETE request
//       final deleteResponse = await client!.delete('/counter');
//       deleteResponse
//         ..assertStatus(200)
//         ..assertBodyContains('Counter reset to: 0');
//
//       // Test method not allowed
//       final putResponse = await client!.put('/counter', null);
//       putResponse.assertStatus(405);
//     });
//
//     test('View with JSON Response', () async {
//       final engine = Engine();
//       final router = Router();
//
//       router.view('/api', ApiView());
//       engine.use(router);
//
//       client = TestClient(RoutedRequestHandler(engine));
//
//       final response = await client!.get('/api');
//       response
//         ..assertStatus(200)
//         ..assertContentType('application/json; charset=utf-8')
//         ..assertJsonContains({
//           'users': [
//             {'id': 1, 'name': 'Alice'},
//             {'id': 2, 'name': 'Bob'},
//           ]
//         });
//     });
//
//     test('View with Route Parameters', () async {
//       final engine = Engine();
//       final router = Router();
//
//       router.view('/users/{id}', ParameterizedView());
//       engine.use(router);
//
//       client = TestClient(RoutedRequestHandler(engine));
//
//       final response = await client!.get('/users/123');
//       response
//         ..assertStatus(200)
//         ..assertBodyEquals('ID: 123');
//     });
//
//     test('Named View Routes', () async {
//       final engine = Engine();
//       final router = Router();
//
//       router.view('/counter', CounterView()).name('counter');
//       engine.use(router);
//
//       // Check that the route was registered with the correct name
//       final routes = engine.getAllRoutes();
//       final counterRoute =
//           routes.firstWhere((r) => r.path == '/counter' && r.method == 'GET');
//       expect(counterRoute.name, equals('counter'));
//     });
//
//     test('View in Router Group', () async {
//       final engine = Engine();
//       final router = Router(groupName: 'api');
//
//       router
//           .group(
//             path: '/v1',
//             builder: (v1) {
//               v1.view('/counter', CounterView()).name('counter');
//             },
//           )
//           .name('v1');
//
//       engine.use(router);
//       engine.printRoutes();
//
//       client = TestClient(RoutedRequestHandler(engine));
//
//       final response = await client!.get('/v1/counter');
//       response
//         ..assertStatus(200)
//         ..assertBody('Counter: 0');
//
//       // Check that the route was registered with the correct name
//       final routes = engine.getAllRoutes();
//       final counterRoute = routes
//           .firstWhere((r) => r.path == '/v1/counter' && r.method == 'GET');
//       expect(counterRoute.name, equals('api.v1.counter'));
//     });
//
//     test('View with Middleware', () async {
//       final engine = Engine();
//       final router = Router();
//
//       // Create a simple logging middleware
//       final logs = <String>[];
//
//       loggingMiddleware(EngineContext context) async {
//         logs.add('Request to: ${context.uri.path}');
//         await context.next();
//         logs.add('Response from: ${context.request.uri.path}');
//       }
//
//       router.view('/counter', CounterView(), middlewares: [loggingMiddleware]);
//       engine.use(router);
//
//       client = TestClient(RoutedRequestHandler(engine));
//
//       await client!.get('/counter');
//
//       expect(
//           logs,
//           equals([
//             'Request to: /counter',
//             'Response from: /counter',
//           ]));
//     });
//   });
// }
