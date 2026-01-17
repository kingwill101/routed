import 'package:routed/routed.dart';

Future<void> main(List<String> args) async {
  final engine = await Engine.createFull();

  final events = await engine.make<EventManager>();

  events.listen((BeforeRoutingEvent event) {
    print(
      '[before] ${event.context.request.method} ${event.context.request.uri}',
    );
  });

  events.listen((RouteMatchedEvent event) {
    print(
      '[matched] ${event.route.name ?? '-'} -> ${event.context.request.path}',
    );
  });

  events.listen((RouteNotFoundEvent event) {
    print(
      '[not-found] ${event.context.request.method} ${event.context.request.path}',
    );
  });

  events.listen((RoutingErrorEvent event) {
    print('[error] ${event.error}');
  });

  events.listen((AfterRoutingEvent event) {
    print('[after] status ${event.context.response.statusCode}');
  });

  engine.get('/', (ctx) => ctx.string('Hello, Router Events!')).name('home');
  engine.get('/boom', (ctx) => throw StateError('Boom!')).name('boom');

  await engine.serve(host: '127.0.0.1', port: 8081);
}
