import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:server_storage/src/storage_manager.dart';

/// Selects a local storage root using application defaults.
///
/// The precedence is [configuredRoot], then [storageRoot] for the `local`
/// disk, then `storage/app` for the `local` disk or `storage/<diskName>` for
/// another disk name. This function only chooses a string; it does not create
/// the directory or validate that it is writable.
///
/// [configuredRoot] is trimmed before it is returned. [storageRoot] is used
/// as supplied when it is non-empty and [diskName] is `local`.
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

/// Resolves paths inside a local filesystem directory.
///
/// The root is normalized to an absolute path when the disk is constructed.
/// Construction does not create the directory. Supply a [file.FileSystem] to
/// use a test filesystem or a non-default filesystem context.
class LocalStorageDisk implements StorageDisk {
  /// Creates a local disk rooted at [root].
  ///
  /// Relative roots are resolved against [fileSystem]'s current directory.
  /// The selected filesystem is retained for all later path resolution.
  LocalStorageDisk({required String root, file.FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const local.LocalFileSystem(),
      _root = _normalizeRoot(root, fileSystem ?? const local.LocalFileSystem());

  final file.FileSystem _fileSystem;
  final String _root;

  /// Normalizes [root] against [fileSystem]'s current directory.
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

  /// Verifies that [resolved] remains inside [_root].
  ///
  /// Absolute inputs and `..` segments that escape the configured directory
  /// are rejected. This guard is what makes it safe to resolve an untrusted
  /// relative path such as `../../etc/passwd` through this disk.
  void _ensureWithinRoot(String resolved, String original) {
    final pathContext = _fileSystem.path;
    if (pathContext.isAbsolute(original) ||
        !_isSameOrChild(resolved, _root, pathContext.separator)) {
      throw ArgumentError(
        'Path "$original" escapes the configured storage root "$_root".',
      );
    }
  }

  /// Returns whether [candidate] equals [root] or is one of its descendants.
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
