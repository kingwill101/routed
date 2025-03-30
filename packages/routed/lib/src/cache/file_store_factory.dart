import 'package:file/local.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/cache/file_store.dart';
import 'store_factory.dart';

class FileStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    final fileSystem = const LocalFileSystem();
    final directory = fileSystem.directory(config['path']);
    final dynamic permission = config['permission'];
    final int? permissionInt = permission is int ? permission : null;
    return FileStore(directory, permissionInt, null, fileSystem);
  }
}
