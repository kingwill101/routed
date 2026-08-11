// ignore_for_file: depend_on_referenced_packages, unnecessary_import

import 'package:routed/routed.dart';
import 'package:routed_storage/routed_storage.dart';

void main() {
  final router = Router();

  // Serve a single file
  router.staticFile('/download', 'files/img.png');

  // Serve a directory of files
  router.static('/files', 'files');

  // Serve an image with a custom file system
  router.staticFile(
    '/image',
    '/home/kingwill101/code/kmp/untitled1/examples/files/file2.txt',
  );

  final engine = Engine();
  engine.use(router);
  engine.serve(port: 8080);
}
