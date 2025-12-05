import 'dart:io';

import 'package:routed/routed.dart';

import 'lib/app.dart';

Future<void> main(List<String> args) async {
  final engine = await createTodoApp();

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 4000;
  stdout.writeln('Todo demo listening on http://localhost:$port/');
  stdout.writeln(
    'Open multiple browser windows to see Turbo Streams in action.',
  );
  await engine.serve(port: port);
}
