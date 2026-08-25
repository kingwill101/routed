import 'package:routed/routed.dart';

Future<void> main() async {
  // Registration is explicit so the selected provider catalogue is clear.
  registerRoutedProviders();

  final engine = await Engine.create();
  engine
    ..get('/health', (ctx) => ctx.json({'ok': true}))
    ..get('/hello/{name}', (ctx) {
      final name = ctx.params['name'] ?? 'Routed';
      return ctx.json({'message': 'Hello, $name!'});
    });

  await engine.serve(port: 8080);
}
