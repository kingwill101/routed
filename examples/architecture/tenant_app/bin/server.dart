import 'dart:async';
import 'dart:io';

import 'package:routed_architecture_tenant_app/app.dart';
import 'package:routed_io/routed_io.dart';

Future<void> main() async {
  final engine = await createEngine(
    databasePath: Platform.environment['DATABASE_PATH'] ?? ':memory:',
  );
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8081;
  print('Tenant architecture example listening on http://$host:$port');
  final server = await serveIo(engine, host: host, port: port);
  await Completer<void>().future;
  await server.close();
}
