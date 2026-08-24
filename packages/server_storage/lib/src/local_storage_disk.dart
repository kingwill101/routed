import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:server_storage/src/storage_manager.dart';

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
  /// Creates a local disk rooted at [root].
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

    final resolved = pathContext.normalize(pathContext.join(_root, path));
    _ensureWithinRoot(resolved, path);
    return resolved;
  }

  /// Verifies that [resolved] stays inside this disk's [_root], rejecting
  /// absolute inputs and `..` segments that escape the configured storage
  /// directory. Without this guard, untrusted paths such as
  /// `../../etc/passwd` could reach files outside the disk.
  void _ensureWithinRoot(String resolved, String original) {
    final pathContext = _fileSystem.path;
    if (pathContext.isAbsolute(original) ||
        !_isSameOrChild(resolved, _root, pathContext.separator)) {
      throw ArgumentError(
        'Path "$original" escapes the configured storage root "$_root".',
      );
    }
  }

  /// Returns true when [candidate] equals [root] or lies within a
  /// subdirectory of [root].
  static bool _isSameOrChild(String candidate, String root, String separator) {
    if (candidate == root) {
      return true;
    }
    final prefix = root.endsWith(separator) ? root : '$root$separator';
    return candidate.startsWith(prefix);
  }

  /// The normalized absolute root path for this disk.
  String get root => _root;
}
