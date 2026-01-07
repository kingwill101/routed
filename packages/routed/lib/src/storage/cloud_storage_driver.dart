import 'package:file/file.dart' as file;
import 'package:routed/src/config/specs/storage_drivers.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart';

/// Storage disk backed by an S3-compatible cloud filesystem.
class CloudStorageDisk implements StorageDisk {
  CloudStorageDisk({required CloudAdapter adapter, this.diskName})
    : _adapter = adapter;

  final CloudAdapter _adapter;

  /// Name associated with this disk inside the manager.
  final String? diskName;

  /// Exposes the underlying cloud adapter for advanced integrations.
  CloudAdapter get adapter => _adapter;

  @override
  file.FileSystem get fileSystem => _adapter.fileSystem;

  @override
  String resolve(String path) {
    final normalized = adapter.fileSystem.path.normalize(path);
    if (normalized.isEmpty || normalized == '.') {
      return '';
    }
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }
}

/// Builder responsible for configuring cloud-backed storage disks.
class CloudStorageDriver {
  const CloudStorageDriver();

  static const CloudStorageDiskSpec spec = CloudStorageDiskSpec();

  StorageDisk build(StorageDriverContext context) {
    final resolved = _resolveConfig(context);
    final adapter =
        CloudAdapter.fromConfig(DiskConfig.fromMap(resolved.toMap()))
            .diskName(context.diskName);
    return CloudStorageDisk(adapter: adapter, diskName: context.diskName);
  }

  List<ConfigDocEntry> documentation(StorageDriverDocContext context) {
    return spec.docs(pathBase: context.pathBase);
  }

  CloudStorageDiskConfig _resolveConfig(StorageDriverContext context) {
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
}

const CloudStorageDriver cloudStorageDriver = CloudStorageDriver();
