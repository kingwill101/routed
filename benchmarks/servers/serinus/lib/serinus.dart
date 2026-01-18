import 'dart:io';

import 'package:serinus/serinus.dart';

import 'app_module.dart';

Future<void> bootstrap() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8003;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final app = await serinus.createApplication(
    entrypoint: AppModule(),
    host: host,
    port: port,
  );
  await app.serve();
}
