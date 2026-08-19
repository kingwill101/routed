import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:server_contracts/server_contracts.dart';

import 'file_store.dart';
import 'store_factory.dart';

/// Typed options for [FileStore].
class FileStoreConfiguration implements StoreConfiguration {
  const FileStoreConfiguration({
    required this.path,
    this.lockPath,
    this.permission,
    this.fileSystem,
  });

  final String path;
  final String? lockPath;
  final int? permission;
  final FileSystem? fileSystem;
}

/// Creates file-backed stores from [FileStoreConfiguration].
class FileStoreFactory implements StoreFactory<FileStoreConfiguration> {
  @override
  Store create(FileStoreConfiguration configuration) {
    final fileSystem = configuration.fileSystem ?? const LocalFileSystem();
    if (configuration.path.isEmpty) {
      throw ArgumentError('file cache store requires a non-empty path');
    }
    final directory = fileSystem.directory(configuration.path)
      ..createSync(recursive: true);

    Directory? lockDirectory;
    final lockPath = configuration.lockPath;
    if (lockPath != null && lockPath.isNotEmpty) {
      lockDirectory = fileSystem.directory(lockPath)
        ..createSync(recursive: true);
    }

    return FileStore(
      directory,
      configuration.permission,
      lockDirectory,
      fileSystem,
    );
  }
}
