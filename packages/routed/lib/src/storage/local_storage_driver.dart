import 'dart:io' as io;

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/src/config/specs/storage_drivers.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';

/// Stateless helper that encapsulates the built-in `local` storage driver.
class LocalStorageDriver {
  const LocalStorageDriver();

  static const LocalStorageDiskSpec spec = LocalStorageDiskSpec();

  /// Computes the root path for a disk, applying defaults when omitted.
  String resolveRoot(
    String? configuredRoot,
    String diskName, {
    String? storageRoot,
  }) {
    final resolved = configuredRoot?.trim();
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
    final config = _resolveConfig(context);
    final root = resolveRoot(
      config.root,
      context.diskName,
      storageRoot: context.storageRoot,
    );

    return LocalStorageDisk(
      root: root,
      fileSystem: config.fileSystem ?? context.manager.defaultFileSystem,
    );
  }

  /// Documents the configuration accepted by the local driver.
  List<ConfigDocEntry> documentation(StorageDriverDocContext context) {
    return spec.docs(pathBase: context.pathBase);
  }

  LocalStorageDiskConfig _resolveConfig(StorageDriverContext context) {
    final specContext = StorageDriverSpecContext(
      diskName: context.diskName,
      pathBase: 'storage.disks.${context.diskName}',
    );
    final merged = spec.mergeDefaults(
      context.configuration,
      context: specContext,
    );
    return spec.fromMap(merged, context: specContext);
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
    if (pathContext.isAbsolute(root)) {
      return pathContext.normalize(root);
    }

    final envPwd = io.Platform.environment['PWD'];
    final base = (envPwd != null && envPwd.isNotEmpty)
        ? envPwd
        : fileSystem.currentDirectory.path;
    final resolved = pathContext.normalize(pathContext.join(base, root));
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
