import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_app1/app.dart' as app;

Future<void> main(List<String> args) async {
  // Read configuration from environment variables (Docker-friendly)
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  print('Starting Routed server...');
  final Engine engine = await app.createEngine();
  await engine.serve(host: host, port: port, echo: true);
}
