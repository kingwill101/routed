import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/storage/local_storage_driver.dart';
Future<void> main() async {
  print('cwd: ${Directory.current.path}');
  final engine = await Engine.create(
    configOptions: const ConfigLoaderOptions(
      loadEnvFiles: false,
      includeEnvironmentSubdirectory: false,
    ),
  );
  final manager = engine.container.get<StorageManager>();
  final disk = manager.disk('assets');
  if (disk is LocalStorageDisk) {
    print('assets.root: ${disk.root}');
  } else {
    print('assets.disk: $disk');
  }
  print('fs.currentDirectory: ${engine.container.get<EngineConfig>().fileSystem.currentDirectory.path}');
}
