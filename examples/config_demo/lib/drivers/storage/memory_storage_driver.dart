import 'package:file/memory.dart' as memory;
import 'package:path/path.dart' as p;
import 'package:routed/routed.dart';

const String memoryStorageDriverName = 'memory_ephemeral';

void registerMemoryStorageDriver() {
  StorageServiceProvider.registerDriver(
    memoryStorageDriverName,
    (context) {
      final fileSystem = memory.MemoryFileSystem();
      final root =
          context.configuration['root']?.toString() ??
          'memory/${context.diskName}';

      // Ensure the root directory exists inside the virtual file system.
      fileSystem.directory(root).createSync(recursive: true);

      final seed = context.configuration['seed']?.toString();
      if (seed != null && seed.isNotEmpty) {
        final seedFile = fileSystem.file(p.join(root, '.seed'));
        seedFile.createSync(recursive: true);
        seedFile.writeAsStringSync(seed);
      }

      return LocalStorageDisk(root: root, fileSystem: fileSystem);
    },
    documentation: (ctx) => <ConfigDocEntry>[
      ConfigDocEntry(
        path: ctx.path('root'),
        type: 'string',
        description:
            'Virtual directory used as the in-memory disk root (defaults to memory/<name>).',
      ),
      ConfigDocEntry(
        path: ctx.path('seed'),
        type: 'string',
        description:
            'Optional seed value written to the disk for easy verification.',
      ),
    ],
  );
}
