import 'dart:io';

import 'package:routed/routed.dart';
Future<void> main() async {
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8006') ?? 8006;

  final engine = Engine(
    config: EngineConfig(
      features: const EngineFeatures(enableRequestZones: false),
    ),
  );

  engine.get('/', (ctx) {
    return ctx.string('ok');
  });

  engine.get('/json', (ctx) {
    return ctx.json({"ok": true});
  });

  await engine.serve(host: host, port: port, echo: false);
}
