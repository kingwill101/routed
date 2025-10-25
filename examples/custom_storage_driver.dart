import 'package:routed/drivers.dart' as drivers;
import 'package:routed/providers.dart' as providers;
import 'package:routed/routed.dart' as routed;

const String archiveStorageDriver = 'archive';

void registerArchiveStorageDriver() {
  providers.StorageServiceProvider.registerDriver(
    archiveStorageDriver,
    (drivers.StorageDriverContext context) {
      final root = context.configuration['root'];
      final rootString = root is String ? root : root?.toString();
      final resolvedRoot =
          (rootString == null || rootString.trim().isEmpty)
              ? 'storage/${context.diskName}.zip'
              : rootString;

      return drivers.LocalStorageDisk(
        root: resolvedRoot,
        fileSystem: context.manager.defaultFileSystem,
      );
    },
    documentation: (drivers.StorageDriverDocContext ctx) => <routed.ConfigDocEntry>[
      routed.ConfigDocEntry(
        path: ctx.path('root'),
        type: 'string',
        description: 'Archive path backing the $archiveStorageDriver disk.',
        metadata: const {
          'default_note': 'Defaults to storage/<disk_name>.zip when omitted.',
        },
      ),
    ],
  );
}

void main() {
  registerArchiveStorageDriver();
  print('Registered $archiveStorageDriver storage driver');
}
