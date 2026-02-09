import 'dart:io';

import 'package:routed/routed.dart';
import 'package:demo_app/app.dart' as app;

Future<void> main(List<String> args) async {
  // Read configuration from environment variables (Docker-friendly)
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  final Engine engine = await app.createEngine();
  await engine.serve(host: host, port: port);
}
