import 'dart:io';

import 'package:kitchen_sink_example/app.dart';
import 'package:routed/routed.dart';

void main() async {
  final engine = await buildApp(
    databasePath:
        Platform.environment['DATABASE_PATH'] ?? 'storage/kitchen_sink.sqlite',
  );
  await engine.serve(host: '127.0.0.1', port: 8080, echo: true);
}
