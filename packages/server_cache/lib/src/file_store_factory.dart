import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:server_cache/src/file_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for [FileStore].
class FileStoreConfiguration implements StoreConfiguration {
  /// Creates file-store options rooted at [path].
  ///
  /// [lockPath] optionally separates lock files from cache entries.
  const FileStoreConfiguration({
    required this.path,
    this.lockPath,
    this.permission,
    this.fileSystem,
  });

  /// Directory used for cache entries.
  final String path;

  /// Optional directory used for lock files.
  final String? lockPath;

  /// Optional permission mode for created files.
  final int? permission;

  /// File system used to access the directories.
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
