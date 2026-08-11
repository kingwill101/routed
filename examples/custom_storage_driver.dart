import 'package:routed/routed.dart';
import 'package:routed_storage/routed_storage.dart';

const String archiveStorageDriver = 'archive';

StorageDisk buildArchiveDisk(String diskName) {
  final root = 'storage/$diskName.zip';
  return LocalStorageDisk(root: root);
}

void main() {
  final manager = StorageManager();
  manager.registerDisk(archiveStorageDriver, buildArchiveDisk(archiveStorageDriver));
  print(
    'Registered $archiveStorageDriver storage driver: '
    '${manager.disk(archiveStorageDriver).resolve('')}',
  );
}
