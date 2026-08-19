import 'dart:io';

import 'package:routed_platform/app.dart' as app;
import 'package:routed_io/routed_io.dart';

Future<void> main(List<String> args) async {
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final engine = await app.createEngine();
  await serveIo(engine, host: host, port: port);
}
