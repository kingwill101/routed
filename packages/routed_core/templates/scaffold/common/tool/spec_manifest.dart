import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:{{{routed:packageName}}}/app.dart' as app;

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  final manifest = engine.buildRouteManifest();
  stdout.writeln(manifest.toJsonString());
}
