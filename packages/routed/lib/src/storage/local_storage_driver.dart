import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';

/// Stateless helper that encapsulates the built-in `local` storage driver.
class LocalStorageDriver {
  const LocalStorageDriver();

  /// Computes the root path for a disk, applying defaults when omitted.
  String resolveRoot(
    Map<String, dynamic> configuration,
    String diskName, {
    String? storageRoot,
  }) {
    final resolved = parseStringLike(
      configuration['root'],
      context: 'storage.disks.$diskName.root',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    if (storageRoot != null && storageRoot.isNotEmpty && diskName == 'local') {
      return storageRoot;
    }
    return _defaultRootFor(diskName);
  }

  /// Produces a `StorageDisk` backed by the local file system.
  StorageDisk build(StorageDriverContext context) {
    final root = resolveRoot(
      context.configuration,
      context.diskName,
      storageRoot: context.storageRoot,
    );

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

/// Local file system backed disk.
class LocalStorageDisk implements StorageDisk {
  LocalStorageDisk({required String root, file.FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const local.LocalFileSystem(),
      _root = _normalizeRoot(root, fileSystem ?? const local.LocalFileSystem());

  final file.FileSystem _fileSystem;
  final String _root;

  static String _normalizeRoot(String root, file.FileSystem fileSystem) {
    final pathContext = fileSystem.path;
    final currentDir = pathContext.normalize(fileSystem.currentDirectory.path);
    final resolved = pathContext.normalize(
      pathContext.isAbsolute(root) ? root : pathContext.join(currentDir, root),
    );
    return resolved;
  }

  @override
  file.FileSystem get fileSystem => _fileSystem;

  @override
  String resolve(String path) {
    if (path.isEmpty) {
      return _root;
    }
    final pathContext = _fileSystem.path;
    return pathContext.normalize(pathContext.join(_root, path));
  }

  String get root => _root;
}

const LocalStorageDriver localStorageDriver = LocalStorageDriver();
