import 'dart:io' as io;

import 'package:file/chroot.dart' show ChrootFileSystem;
import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:server_storage/src/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart'
    show DiskConfig, Filesystem, FilesystemAdapter;

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
class LocalStorageDisk implements FilesystemStorageDisk {
  /// Creates a local disk rooted at [root].
  ///
  /// Relative roots are resolved against [fileSystem]'s current directory.
  /// The selected filesystem is retained for all later path resolution.
  LocalStorageDisk({required String root, file.FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const local.LocalFileSystem(),
      _root = _normalizeRoot(root, fileSystem ?? const local.LocalFileSystem());

  final file.FileSystem _fileSystem;
  final String _root;

  @override
  late final FilesystemAdapter storage = _RootedFilesystemAdapter(
    rootPath: _root,
    hostFileSystem: _fileSystem,
  );

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

final class _RootedFilesystemAdapter extends FilesystemAdapter {
  _RootedFilesystemAdapter({
    required this.rootPath,
    required this.hostFileSystem,
  }) : super(
         const DiskConfig(driver: 'local'),
         fileSystem: ChrootFileSystem(
           hostFileSystem,
           hostFileSystem.path.canonicalize(rootPath),
         ),
       );

  final String rootPath;
  final file.FileSystem hostFileSystem;

  @override
  Future<bool> setVisibility(String path, String visibility) async {
    if (hostFileSystem is! local.LocalFileSystem) {
      return false;
    }
    if (io.Platform.isWindows) return true;

    final resolved = _resolveHostPath(path);
    final mode = visibility == Filesystem.visibilityPublic ? '644' : '600';
    try {
      final result = await io.Process.run('chmod', [mode, resolved]);
      if (result.exitCode == 0) return true;
      if (config.throw_) {
        throw io.FileSystemException(
          'Unable to set visibility (chmod exited ${result.exitCode}).',
          resolved,
        );
      }
      return false;
    } on Exception {
      if (config.throw_) rethrow;
      return false;
    }
  }

  String _resolveHostPath(String value) {
    final pathContext = hostFileSystem.path;
    if (pathContext.isAbsolute(value)) {
      throw ArgumentError.value(value, 'path', 'Must be relative.');
    }
    final resolved = pathContext.normalize(pathContext.join(rootPath, value));
    if (!LocalStorageDisk._isSameOrChild(
      resolved,
      rootPath,
      pathContext.separator,
    )) {
      throw ArgumentError.value(value, 'path', 'Escapes the storage root.');
    }
    return resolved;
  }
}
