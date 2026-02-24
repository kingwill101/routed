import 'package:routed/src/config/specs/storage_drivers.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:server_data/storage.dart';
import 'package:storage_fs/storage_fs.dart';

/// Builder responsible for configuring cloud-backed storage disks.
class CloudStorageDriver {
  const CloudStorageDriver();

  static const CloudStorageDiskSpec spec = CloudStorageDiskSpec();

  StorageDisk build(StorageDriverContext context) {
    final resolved = _resolveConfig(context);
    final adapter = CloudAdapter.fromConfig(
      DiskConfig.fromMap(resolved.toMap()),
    ).diskName(context.diskName);
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
