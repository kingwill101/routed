import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:{{{routed:packageName}}}/app.dart' as app;

Future<void> main(List<String> args) async {
  // Route inspection must not open host resources or run migrations. The
  // server entrypoint performs normal initialized startup instead.
  final engine = await app.createEngine(initialize: false);
  final manifest = engine.buildRouteManifest();
  stdout.writeln(manifest.toJsonString());
}
