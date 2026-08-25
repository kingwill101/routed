import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;

/// Resolves application paths against a configured storage disk.
///
/// Implementations decide how a path is represented. A local disk returns an
/// absolute filesystem path, while a cloud disk normally returns an object
/// key. Implementations should reject paths that violate their own storage
/// boundary.
abstract class StorageDisk {
  /// The filesystem associated with this disk.
  ///
  /// For a cloud disk this is the adapter's cloud filesystem. The value is
  /// exposed so framework adapters can perform storage operations without
  /// depending on a concrete disk implementation.
  file.FileSystem get fileSystem;

  /// Resolves the application-relative [path] for this disk.
  ///
  /// The returned form is implementation-specific. Callers should pass
  /// relative, untrusted paths to this method instead of constructing paths
  /// by joining a disk root themselves.
  String resolve(String path);
}

/// Registers and selects named storage disks for an application.
///
/// A manager is an in-memory registry. Constructing it does not create a
/// directory, connect to a cloud service, or register a `local` disk. The
/// default name starts as `local`, so register that disk before resolving a
/// path unless an application selects another name.
class StorageManager {
  /// Creates a manager with [defaultFileSystem] available to disk factories.
  ///
  /// The manager does not create disks from this filesystem automatically.
  /// Supplying an in-memory filesystem is useful when constructing disks in
  /// tests; production code normally uses the default local filesystem.
  StorageManager({file.FileSystem? defaultFileSystem})
    : _defaultFileSystem = defaultFileSystem ?? const local.LocalFileSystem();

  final Map<String, StorageDisk> _disks = {};
  String _defaultDisk = 'local';
  final file.FileSystem _defaultFileSystem;

  /// Removes every registered disk.
  ///
  /// This does not reset [defaultDisk] or delete any files. Register a disk
  /// under the selected default name before using [disk] or [resolve] again.
  void clear() {
    _disks.clear();
  }

  /// Sets the name used when a disk is not selected explicitly.
  ///
  /// The name is not required to be registered at this point. A later call to
  /// [disk] or [resolve] throws [StateError] until a matching disk is added.
  ///
  /// Throws [ArgumentError] when [name] is empty.
  void setDefault(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Default disk name cannot be empty.');
    }
    _defaultDisk = name;
  }

  /// Registers [disk] under [name], replacing an existing registration.
  ///
  /// Registration changes only this in-memory registry; it does not create or
  /// remove files and does not close the replaced disk.
  ///
  /// Throws [ArgumentError] when [name] is empty.
  void registerDisk(String name, StorageDisk disk) {
    if (name.isEmpty) {
      throw ArgumentError('Disk name cannot be empty.');
    }
    _disks[name] = disk;
  }

  /// Returns whether a disk named [name] is registered.
  bool hasDisk(String name) => _disks.containsKey(name);

  /// A snapshot of the registered disk names in insertion order.
  List<String> get diskNames => _disks.keys.toList(growable: false);

  /// Resolves [path] against [disk], or against [defaultDisk] when omitted.
  ///
  /// The selected disk controls normalization and path-safety behavior. This
  /// method does not read from or write to the filesystem.
  ///
  /// Throws [StateError] when the selected disk is not registered.
  String resolve(String path, {String? disk}) {
    return this.disk(disk).resolve(path);
  }

  /// Returns the disk named [name], or the default disk when omitted or empty.
  ///
  /// Throws [StateError] when the selected disk is not registered.
  StorageDisk disk([String? name]) {
    final key = (name == null || name.isEmpty) ? _defaultDisk : name;
    final disk = _disks[key];
    if (disk == null) {
      throw StateError('Storage disk "$key" is not configured.');
    }
    return disk;
  }

  /// The name selected for implicit disk lookups.
  String get defaultDisk => _defaultDisk;

  /// The filesystem supplied to code that creates disks from this manager.
  ///
  /// Reading this property does not create a disk or alter the registry.
  file.FileSystem get defaultFileSystem => _defaultFileSystem;
}
