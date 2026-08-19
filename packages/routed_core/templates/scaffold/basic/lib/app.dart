import 'package:routed_core/routed_core.dart';

Future<Engine> createEngine({bool initialize = true}) async {
  final engine = Engine(
    providers: [
      CoreServiceProvider(),
      RoutingServiceProvider(),
    ],
  );

  if (initialize) {
    await engine.initialize();
  }

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to {{{routed:humanName}}}!'});
  });

  return engine;
}
