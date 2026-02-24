import 'package:routed/src/config/specs/storage_drivers.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:server_data/storage.dart';

/// {@template local_storage_root}
/// Resolves local disk roots with sensible defaults.
///
/// Order: explicit disk root → storage root for the `local` disk →
/// `storage/app` or `storage/<disk>`.
///
/// Example:
/// ```dart
/// final root = localStorageDriver.resolveRoot(null, 'local');
/// ```
/// {@endtemplate}

/// {@macro local_storage_root}
class LocalStorageDriver {
  const LocalStorageDriver();

  static const LocalStorageDiskSpec spec = LocalStorageDiskSpec();

  /// {@macro local_storage_root}
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

const LocalStorageDriver localStorageDriver = LocalStorageDriver();
