import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:server_cache/src/file_store.dart';
import 'package:server_cache/src/store_factory.dart';
import 'package:server_contracts/server_contracts.dart';

/// Typed options for creating a [FileStore].
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
  ///
  /// [FileStoreFactory] creates this directory and any missing parents before
  /// returning the store. An empty path is rejected.
  final String path;

  /// Optional directory used for lock files.
  ///
  /// When omitted or empty, the store uses [path] for lock files as well.
  final String? lockPath;

  /// Optional permission mode for created cache files.
  ///
  /// The value is passed to [FileStore] as a backend-specific permission mode;
  /// it is not interpreted by the factory.
  final int? permission;

  /// File system used to access the directories.
  ///
  /// Defaults to a [LocalFileSystem]. Supply an in-memory or test file system
  /// when the application should not touch the host file system.
  final FileSystem? fileSystem;
}

/// Creates file-backed stores from typed [FileStoreConfiguration] options.
class FileStoreFactory implements StoreFactory<FileStoreConfiguration> {
  /// Creates a file store and eagerly creates its configured directories.
  ///
  /// Throws an argument error when the configured path is empty. File-system
  /// errors from directory creation are allowed to propagate to the caller.
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
