import 'dart:io';

import 'package:config_demo/app.dart' as app;
import 'package:routed/routed.dart';

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  final manifest = engine.buildRouteManifest();
  stdout.writeln(manifest.toJsonString());
}
