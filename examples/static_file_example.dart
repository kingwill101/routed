import 'dart:io';

import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final router = Router();

  // Create some test files and directories
  Directory('public').createSync();

  Directory('public/images').createSync();

  // Create some test files
  File('public/index.html')
    ..createSync()
    ..writeAsStringSync('<h1>Welcome to Static File Server</h1>');

  File('public/styles.css')
    ..createSync()
    ..writeAsStringSync('body { color: blue; }');

  File('public/images/logo.txt')
    ..createSync()
    ..writeAsStringSync('Logo placeholder');

  // Serve static files from the public directory
  router.static('/public', 'public');

  // Serve static files with directory listing enabled
  router.static('/files', 'public', listDirectory: true);

  // Serve a single static file
  router.staticFile('/logo', 'public/images/logo.txt');

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
