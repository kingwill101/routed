import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/contracts/cache/store.dart';

import 'store_factory.dart';

class FileStoreFactory implements StoreFactory {
  @override
  Store create(Map<String, dynamic> config) {
    final fileSystem = const LocalFileSystem();
    final path = config['path'];
    if (path is! String || path.isEmpty) {
      throw ArgumentError('file cache store requires a non-empty "path"');
    }
    final directory = fileSystem.directory(path)..createSync(recursive: true);

    Directory? lockDirectory;
    final lockPath = config['lock_path'];
    if (lockPath is String && lockPath.isNotEmpty) {
      lockDirectory = fileSystem.directory(lockPath)
        ..createSync(recursive: true);
    }

    final dynamic permission = config['permission'];
    final int? permissionInt;
    if (permission is int) {
      permissionInt = permission;
    } else if (permission is String) {
      permissionInt =
          int.tryParse(permission, radix: 8) ?? int.tryParse(permission);
    } else {
      permissionInt = null;
    }

    return FileStore(directory, permissionInt, lockDirectory, fileSystem);
  }
}
