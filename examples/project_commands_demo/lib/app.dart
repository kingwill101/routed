import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create();

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Hello from the project commands demo!'});
  });

  engine.get('/health', (ctx) async {
    return ctx.json({'status': 'ok'});
  });

  return engine;
}
