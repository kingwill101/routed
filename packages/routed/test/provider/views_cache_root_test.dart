import 'dart:io';

import 'package:file/local.dart' as local;
import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('view engine does not change cache root resolution', () async {
    final tempDir = Directory.systemTemp.createTempSync('routed-views-cache-');
    final fs = const local.LocalFileSystem();
    final originalCwd = fs.currentDirectory;
    addTearDown(() {
      if (originalCwd.existsSync()) {
        fs.currentDirectory = originalCwd.path;
      }
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final viewsDir = Directory('${tempDir.path}/views')..createSync();
    fs.currentDirectory = viewsDir.path;
    final storageRoot = '${tempDir.path}/storage/app';

    final engine = await Engine.createFull(
      configOptions: ConfigLoaderOptions(
        loadEnvFiles: false,
        includeEnvironmentSubdirectory: false,
        fileSystem: fs,
        defaults: {
          'app': {'root': tempDir.path},
          'storage': {
            'disks': {
              'local': {'driver': 'local', 'root': storageRoot},
            },
          },
          'views': {'path': viewsDir.path},
          'cache': {
            'stores': {
              'file': {'driver': 'file', 'path': 'storage/framework/cache'},
            },
          },
        },
      ),
    );

    final cacheManager = engine.container.get<CacheManager>();
    final store = cacheManager.store('file').getStore();
    expect(store, isA<FileStore>());

    final cacheDir = (store as FileStore).directory.path;
    expect(
      cacheDir,
      equals(
        fs.path.normalize(
          fs.path.join(tempDir.path, 'storage', 'framework', 'cache'),
        ),
      ),
    );
  });
}
