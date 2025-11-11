import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:routed/src/cache/file_store.dart';
import 'package:routed/src/contracts/cache/store.dart';

import 'store_factory.dart';

/// A [StoreFactory] implementation that creates [FileStore] instances.
///
/// This factory configures a [FileStore] based on a provided map of settings,
/// allowing specification of the cache directory path, an optional lock
/// directory, and file permissions.
class FileStoreFactory implements StoreFactory {
  /// Creates a new [FileStore] instance based on the provided [config].
  ///
  /// The [config] map requires a `'path'` entry which specifies the directory
  /// where cache files will be stored. This path must be a non-empty [String].
  ///
  /// An optional `'lock_path'` entry ([String]) can be provided to specify
  /// a separate directory for lock files. If not provided, lock files will
  /// be stored within the main cache directory.
  ///
  /// An optional `'permission'` entry can be provided to set file permissions
  /// for newly created cache files. It can be an [int] (e.g., `0o755`) or
  /// a [String] representing the octal or decimal permission (e.g., `'755'` or `'0755'`).
  ///
  /// Throws an [ArgumentError] if the `'path'` is not a valid non-empty string.
  ///
  /// Example usage:
  /// ```dart
  /// final factory = FileStoreFactory();
  ///
  /// // Basic usage with only a path
  /// final store1 = factory.create({
  ///   'path': '/tmp/my_cache',
  /// });
  ///
  /// // Usage with custom permissions and a separate lock directory
  /// final store2 = factory.create({
  ///   'path': '/var/cache/app_data',
  ///   'lock_path': '/var/lock/app_data',
  ///   'permission': 0o644, // Read/write for owner, read-only for others
  /// });
  ///
  /// // Usage with string permission
  /// final store3 = factory.create({
  ///   'path': 'cache_files',
  ///   'permission': '777', // Full permissions
  /// });
  /// ```
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
