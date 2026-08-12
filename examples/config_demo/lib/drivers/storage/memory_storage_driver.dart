import 'package:file/memory.dart' as memory;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';
import 'package:routed_storage/routed_storage.dart';

const String memoryStorageDriverName = 'memory_ephemeral';

/// Registers an ephemeral in-memory disk on the given [manager].
void registerMemoryStorageDriver(StorageManager manager, {String? root}) {
  final fileSystem = memory.MemoryFileSystem();
  final diskRoot = root ?? 'memory/$memoryStorageDriverName';

  // Ensure the root directory exists inside the virtual file system.
  fileSystem.directory(diskRoot).createSync(recursive: true);

  manager.registerDisk(
    memoryStorageDriverName,
    LocalStorageDisk(root: diskRoot, fileSystem: fileSystem),
  );
}

/// Registers a transient in-memory disk named `transient`.
void registerTransientStorageDriver(StorageManager manager) {
  final fileSystem = memory.MemoryFileSystem();
  fileSystem.directory('memory/transient').createSync(recursive: true);
  manager.registerDisk(
    'transient',
    LocalStorageDisk(root: 'memory/transient', fileSystem: fileSystem),
  );
}

/// Optional seed support kept for parity with the old config-driven driver.
void seedMemoryStorage(StorageManager manager, String seed) {
  final disk = manager.disk(memoryStorageDriverName);
  final seedFile = disk.fileSystem.file(p.join('memory', memoryStorageDriverName, '.seed'));
  seedFile.createSync(recursive: true);
  seedFile.writeAsStringSync(seed);
}
