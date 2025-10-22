// ignore_for_file: depend_on_referenced_packages

import 'package:routed/routed.dart';

void main() {
  final router = Router();

  // Serve a single file
  router.get('/download', (c) async {
    await c.fileAttachment('files/img.png', 'screenshot.png');
  });

  // Serve a directory
  router.get('/files/{file}', (c) async {
    final filePath = c.param('file');
    await c.file('files/$filePath');
    c.abort();
  });

  // Serve an image
  router.get('/image', (c) async {
    await c.file(
      '/home/kingwill101/code/kmp/untitled1/examples/files/file2.txt',
    );
    c.abort();
  });

  final engine = Engine();
  engine.use(router);
  engine.serve(port: 8080);
}
