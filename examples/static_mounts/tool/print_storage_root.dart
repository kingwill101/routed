import 'dart:io';

import 'package:routed/routed.dart';

Future<void> main() async {
  print('cwd: ${Directory.current.path}');
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedStorageProvider(
        configuration: StorageConfig(
          disks: {
            'local': const LocalStorageDiskConfig(root: 'storage/app'),
            'assets': const LocalStorageDiskConfig(root: 'public'),
          },
        ),
      ),
    ],
  );
  final manager = engine.container.get<StorageManager>();
  final disk = manager.disk('assets');
  if (disk is LocalStorageDisk) {
    print('assets.root: ${disk.root}');
  } else {
    print('assets.disk: $disk');
  }
  print(
    'fs.currentDirectory: ${engine.container.get<EngineConfig>().fileSystem.currentDirectory.path}',
  );
}
