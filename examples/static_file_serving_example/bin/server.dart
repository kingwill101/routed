import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/file_handler.dart';

void main(List<String> args) async {
  final engine = Engine();
  final fs = MemoryFileSystem();
  final router = Router();

  // Create a test directory with some files
  final dir = fs.directory("files")..createSync();

  // Create a text file
  dir.childFile('test_file.txt')
    ..createSync()
    ..writeAsStringSync('Routed Web Framework');

  // Create a nested directory with files
  final nestedDir = dir.childDirectory('nested')..createSync();
  nestedDir.childFile('nested_file.txt')
    ..createSync()
    ..writeAsStringSync('Nested file content');

  // Serve static files with directory listing enabled
  router.staticFS(
      '/static', Dir(dir.path, listDirectory: true, fileSystem: fs));

  // Serve a single static file
  router.staticFile('/file', '${dir.path}/test_file.txt', fs);

  engine.use(router);
  await engine.serve(host: '127.0.0.1', port: 8080);
}
