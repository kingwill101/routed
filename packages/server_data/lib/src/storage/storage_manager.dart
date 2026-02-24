import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;

/// Represents a configured storage disk.
abstract class StorageDisk {
  /// The underlying file system used by this disk.
  file.FileSystem get fileSystem;

  /// Resolves [path] to an absolute path on this disk.
  String resolve(String path);
}

/// Manages configured storage disks.
class StorageManager {
  StorageManager({file.FileSystem? defaultFileSystem})
    : _defaultFileSystem = defaultFileSystem ?? const local.LocalFileSystem();

  final Map<String, StorageDisk> _disks = {};
  String _defaultDisk = 'local';
  final file.FileSystem _defaultFileSystem;

  /// Clears all registered disks.
  void clear() {
    _disks.clear();
  }

  /// Sets the default disk name.
  void setDefault(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Default disk name cannot be empty.');
    }
    _defaultDisk = name;
  }

  /// Registers a disk implementation under [name].
  void registerDisk(String name, StorageDisk disk) {
    _disks[name] = disk;
  }

  /// Returns whether a disk named [name] exists.
  bool hasDisk(String name) => _disks.containsKey(name);

  /// Resolves [path] against the selected [disk] (default disk if omitted).
  String resolve(String path, {String? disk}) {
    return this.disk(disk).resolve(path);
  }

  /// Returns the disk named [name] (or the default disk if omitted).
  StorageDisk disk([String? name]) {
    final key = (name == null || name.isEmpty) ? _defaultDisk : name;
    final disk = _disks[key];
    if (disk == null) {
      throw StateError('Storage disk "$key" is not configured.');
    }
    return disk;
  }

  /// The configured default disk name.
  String get defaultDisk => _defaultDisk;

  /// The default file system used when creating new disks.
  file.FileSystem get defaultFileSystem => _defaultFileSystem;
}
