import 'dart:io';

import 'package:routed/routed.dart';
import 'package:demo_app/app.dart' as app;

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  final manifest = engine.buildRouteManifest();
  stdout.writeln(manifest.toJsonString());
}
