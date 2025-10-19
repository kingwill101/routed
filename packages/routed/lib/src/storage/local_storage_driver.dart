import 'package:file/file.dart' as file;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';

/// Stateless helper that encapsulates the built-in `local` storage driver.
class LocalStorageDriver {
  const LocalStorageDriver();

  /// Computes the root path for a disk, applying defaults when omitted.
  String resolveRoot(Map<String, dynamic> configuration, String diskName) {
    return parseStringLike(
          configuration['root'],
          context: 'storage.disks.$diskName.root',
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        ) ??
        _defaultRootFor(diskName);
  }

  /// Produces a `StorageDisk` backed by the local file system.
  StorageDisk build(StorageDriverContext context) {
    final root = resolveRoot(context.configuration, context.diskName);

    return LocalStorageDisk(
      root: root,
      fileSystem: _resolveFileSystem(context.configuration, context.manager),
    );
  }

  /// Documents the configuration accepted by the local driver.
  List<ConfigDocEntry> documentation(StorageDriverDocContext context) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('root'),
        type: 'string',
        description:
            'Filesystem path used as the disk root (defaults to storage/app for the local disk, or storage/<name> for other disks).',
      ),
      ConfigDocEntry(
        path: context.path('file_system'),
        type: 'FileSystem',
        description:
            'Optional file system override used when operating the local disk.',
      ),
    ];
  }

  file.FileSystem _resolveFileSystem(
    Map<String, dynamic> rawConfig,
    StorageManager manager,
  ) {
    final fs = rawConfig['file_system'];
    if (fs is file.FileSystem) {
      return fs;
    }
    return manager.defaultFileSystem;
  }

  String _defaultRootFor(String diskName) {
    if (diskName == 'local') {
      return 'storage/app';
    }
    return 'storage/$diskName';
  }
}

const LocalStorageDriver localStorageDriver = LocalStorageDriver();
