import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;

import 'storage_manager.dart';

/// Resolves local storage roots with sensible defaults.
///
/// Order: explicit [configuredRoot] -> [storageRoot] for the `local` disk ->
/// `storage/app` or `storage/<diskName>`.
String resolveLocalStorageRoot(
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
  if (diskName == 'local') {
    return 'storage/app';
  }
  return 'storage/$diskName';
}

/// Local file system backed disk.
class LocalStorageDisk implements StorageDisk {
  LocalStorageDisk({required String root, file.FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const local.LocalFileSystem(),
      _root = _normalizeRoot(root, fileSystem ?? const local.LocalFileSystem());

  final file.FileSystem _fileSystem;
  final String _root;

  /// Normalizes a disk root against the filesystem context.
  static String _normalizeRoot(String root, file.FileSystem fileSystem) {
    final pathContext = fileSystem.path;
    if (pathContext.isAbsolute(root)) {
      return pathContext.normalize(root);
    }

    final resolved = pathContext.normalize(
      pathContext.join(fileSystem.currentDirectory.path, root),
    );
    return resolved;
  }

  @override
  file.FileSystem get fileSystem => _fileSystem;

  @override
  String resolve(String path) {
    if (path.isEmpty) {
      return _root;
    }
    final pathContext = _fileSystem.path;
    return pathContext.normalize(pathContext.join(_root, path));
  }

  String get root => _root;
}
